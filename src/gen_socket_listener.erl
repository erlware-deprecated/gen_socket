%%%-------------------------------------------------------------------
%%% @author Serge Aleynikov <saleyn@gmail.com>
%%% @copyright (C) 2007, 2008, Serge Aleynikov
%%% @doc Generic socket listener.  See:
%%%      [http://www.trapexit.org/index.php/Building_a_Non-blocking_TCP_server_using_OTP_principles]
%%% @end
%%% Created 2007-07-14
%%%-------------------------------------------------------------------
-module(gen_socket_listener).
-author('saleyn@gmail.com').

-behaviour(gen_server).

%% External API
-export([start_link/5]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-record(state, {
                listener,       % Listening socket
                acceptor,       % Asynchronous acceptor's internal reference
                module,         % client handling module
                sup_name,       % Supervisor's registered name
                uds_port        % Unix Domain Socket driver port.
               }).

%%--------------------------------------------------------------------
%% @spec (ListenerSupName, ConnectionSupName, Port::integer(),
%%        Module, Options::list())  -> Result
%%          ListenerSupName   = atom()
%%          ConnectionSupName = atom()
%%          Result            = {ok, Pid} | {error, Reason}
%%          Options           = [ Option ]
%%          Option            = {socket_opts, SocketOptions::list()}
%% @doc Called by a supervisor to start the listening process.
%%      `ListenerSupName' is the name given to the listening process
%%      supervisor. `ConnectionSupName' is the name given to the
%%      supervisor of spawned client connections.  The listener will be
%%      started on the given `Port'. `Module' is the implementation
%%      of the user-level protocol.
%%
%%      `Options' is a list of listener options. Currently the only
%%      supported option is {socket_opts, SocketOptions::list()}, where
%%      `SocketOptions' is a list of options supported by `gen_tcp:listen/2'.
%%
%% This module must implement a `set_socket/2' function.
%% @end
%%----------------------------------------------------------------------
start_link(ListenerSupName, ConnectionSupName, Port, Module, Options)
  when is_atom(ListenerSupName), is_atom(ConnectionSupName),
       is_integer(Port), is_atom(Module) ->
    gen_server:start_link({local, ListenerSupName}, ?MODULE,
                          [ConnectionSupName, Port, Module, Options], []).

%%%------------------------------------------------------------------------
%%% Callback functions from gen_server
%%%------------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initiates the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([ConnSupName, Port, Module, Options]) ->
    process_flag(trap_exit, true),
    Opts = make_socket_opts(Port, Options),
    try
        case listen_socket(Port, Opts) of
            {ok, LSock} ->
                UdsPort = undefined;
            {ok, UdsPort, LSock} ->
                ok;
            Error ->
                UdsPort = none, LSock = none, throw(Error)
        end,

        % Create first accepting process
        {ok, Ref} = prim_inet:async_accept(LSock, -1),
        {ok, #state{listener = LSock,
                    acceptor = Ref,
                    module   = Module,
                    sup_name = ConnSupName,
                    uds_port = UdsPort}}
    catch What ->
        {stop, What}
    end.

%% @private
%% Return a list of socket options for the given port.
make_socket_opts(Port, Options) ->
    case lists:keysearch(socket_opts, 1, Options) of
        {value, SocketOptions} ->
            ok;
        false ->
            SocketOptions = [binary, {packet, raw}, {reuseaddr, true},
                             {keepalive, true}, {active, false}, {backlog, 30}]
    end,

    case is_integer(Port) of
        true -> SocketOptions;
        false -> lists:keydelete(backlog, 1, SocketOptions)
    end.

%% @private
%% Open the listening socket with the given options.
listen_socket(Port, Opts) when is_integer(Port) ->
    % Open an INET socket
    gen_tcp:listen(Port, Opts);
listen_socket(Filename, Opts) when is_list(Filename) ->
    % Open a UDS socket
    try
        case unixdom_drv:start() of
            {ok, DrvPort} ->
                ok;
        {error, Reason} ->
                DrvPort = undefined, throw({error, Reason});
        {'EXIT', Reason} ->
                DrvPort = undefined, throw({error, Reason})
        end,
        file:delete(Filename),
        case unixdom_drv:listen(DrvPort, Filename, Opts) of
            {ok, LSock} ->
                {ok, DrvPort, LSock};
            Error ->
                Error
        end
    catch What ->
        What
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(Request, _From, State) ->
    {stop, {unknown_call, Request}, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info({inet_async, ListSock, Ref, {ok, CliSocket}},
            #state{listener=ListSock, acceptor=Ref,
                   module=Module, sup_name=SupName} = State) ->
    case set_sockopt(ListSock, CliSocket) of
        ok ->
            % New client connected - spawn a new process using the
            % simple_one_for_one supervisor.
            {ok, Pid} = gen_socket_connection_sup:start_client(SupName),
            ok = gen_tcp:controlling_process(CliSocket, Pid),
            % Instruct the new process that it owns the socket.
            Module:set_socket(Pid, CliSocket),
            {ok, NewRef} = prim_inet:async_accept(ListSock, -1),
            {noreply, State#state{acceptor=NewRef}};
        {error, Reason} ->
            error_logger:error_msg("Error setting socket options: ~p.\n", [Reason]),
            {stop, Reason, State}
    end;

handle_info({inet_async, ListSock, Ref, Error},
            #state{listener=ListSock, acceptor=Ref} = State) ->
    error_logger:error_msg("Error in socket acceptor: ~p.\n", [Error]),
    {stop, Error, State};

handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, #state{uds_port=UdsPort, listener=LSock}) ->
    case UdsPort of
    undefined ->
        gen_tcp:close(LSock);
    _ ->
        unixdom_drv:tcp_close(UdsPort, LSock)
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%------------------------------------------------------------------------
%%% Internal functions
%%%------------------------------------------------------------------------

%% @private
%% @doc Taken from prim_inet.  We are merely copying some socket options
%% from the listening socket to the new client socket.
set_sockopt(ListSock, CliSocket) ->
    true = inet_db:register_socket(CliSocket, inet_tcp),
    case prim_inet:getopts(ListSock, [active, nodelay, keepalive,
                                      delay_send, priority, tos]) of
    {ok, Opts} ->
        case prim_inet:setopts(CliSocket, Opts) of
            ok ->
                ok;
            Error ->
                gen_tcp:close(CliSocket), Error
        end;
    Error ->
        gen_tcp:close(CliSocket), Error
    end.
