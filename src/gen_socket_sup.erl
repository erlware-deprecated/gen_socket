%%%-------------------------------------------------------------------
%%% @author Serge Aleynikov <saleyn@gmail.com>
%%% @copyright (C) 2007, 2008, Serge Aleynikov
%%% @doc Generic socket listener supervisor. See:
%%%      [http://www.trapexit.org/index.php/Building_a_Non-blocking_TCP_server_using_OTP_principles]
%%%
%%% <pre>
%%%    Here is how to add this server to a supervision tree:
%%%
%%%    init([]) ->
%%%        % Socket Server supervisor specification
%%%        SupSpec =
%%%            gen_socket_sup:get_supervisor_spec(
%%%                _NamePrefix    = "myserver",
%%%                _ListenPort    = 9999,
%%%                _HandlerModule = client_handling_module,
%%%                _Args          = ServerArgs::list()
%%%            ),
%%%
%%%        {ok, {_SupFlags = {one_for_one, 3, 60}, [SupSpec]} }.
%%% </pre>
%%% @end
%%% Created 2007-07-14
%%%-------------------------------------------------------------------
-module(gen_socket_sup).
-author('saleyn@gmail.com').

-behaviour(supervisor).

%% External API
-export([start_link/6, start_link/5,
         get_supervisor_spec/5, get_supervisor_spec/4,
         handle_socket/3]).

%% Supervisor callbacks
-export([init/1]).

-define(MAX_RESTART, 5).
-define(MAX_TIME, 60).

%%-------------------------------------------------------------------------
%% @spec (SupNamePrefix, Port, HandlerModule, ServerArgs, Options)
%%                                                   -> SupSpec::tuple()
%%         SupNamePrefix  = string()
%%         Port           = integer() | [integer()]
%%         HandlerModule  = atom()
%%         ServerArgs     = [term()]
%%         Options        = list()
%%
%% @doc Generates the supervisor specification that can be used by the
%%      application top supervisor's init/1 callback function that
%%      wants to link socket server under its supervision tree.
%%      `SupNamePrefix' is the prefix used for naming the main supervisor
%%      (SupNamePrefix ++ "gen_socket_sup") and the connection supervisor
%%      (SupNamePrefix ++ "connection_sup").
%%
%%      `HandlerModule' is the module implementing a user protocol process,
%%      whose `start_link' function should accept `ServerArgs'.
%%
%%      `Options' is a list of options that will be passed to the
%%      listener server.
%% @see gen_socket_listener:start_link/5
%% @end
%%-------------------------------------------------------------------------
get_supervisor_spec(SupNamePrefix, Port, HandlerModule, ServerArgs, Options) ->
    SupName = create_name(SupNamePrefix, "gen_socket"),
    ListenerArgs = [SupName, SupNamePrefix, Port,
                    HandlerModule, ServerArgs, Options],
    % Socket Listener
    {SupName,                    % Id       = internal id
     {gen_socket_sup,
      start_link, ListenerArgs}, % StartFun = {M, F, A}
     permanent,                  % Restart  = permanent | transient | temporary
     2000,                       % Shutdown = brutal_kill | int() >= 0 | infinity
     worker,                     % Type     = worker | supervisor
     [gen_socket_sup]            % Modules  = [Module] | dynamic
    }.

%%-------------------------------------------------------------------------
%% @spec (SupNamePrefix, Port, HandlerModule, ServerArgs) -> SupSpec::tuple()
%%
%% @doc This is equivalent to get_supervisor_spec/5 with an empty
%% set of options.
%% @end
%%-------------------------------------------------------------------------
get_supervisor_spec(SupNamePrefix, Port, HandlerModule, ServerArgs) ->
    get_supervisor_spec(SupNamePrefix, Port, HandlerModule, ServerArgs, []).

%%-------------------------------------------------------------------------
%% @spec (SupNamePrefix, HandlerModule, Socket) -> {ok, Pid}
%%
%% @doc Given a socket (made from, e.g., gen_tcp:connect), start a handler
%% module on the socket. This function must be called by the socket owner.
%% @end
%%-------------------------------------------------------------------------
handle_socket(SupNamePrefix, HandlerModule, Socket) ->
    ConnectionSupName = create_connection_sup_name(SupNamePrefix),
    {ok, Pid} = gen_socket_connection_sup:start_client(ConnectionSupName),
    ok = gen_tcp:controlling_process(Socket, Pid),
    HandlerModule:set_socket(Pid, Socket),
    {ok, Pid}.

%%-------------------------------------------------------------------------
%% @spec (RegisteredName, SupNamePrefix, Port,
%%        HandlerModule, ServerArgs, Options) -> {ok, Pid}
%%         RegisteredName = string()
%%         SupNamePrefix  = atom()
%%         Port           = integer() | [integer()]
%%         HandlerModule  = atom()
%%         ServerArgs     = [term()]
%%         Options        = list()
%%
%% @doc To be called by the top-level application supervisor to
%% start socket server listener.
%%
%% `RegisteredName' is the registered name of the socket server's supervisor.
%% @see get_supervisor_spec/5
%% @end
%%-------------------------------------------------------------------------
start_link(RegisteredName, SupNamePrefix, Port,
           HandlerModule, ServerArgs, Options)
  when is_atom(RegisteredName), is_list(SupNamePrefix), is_list(Options) ->
    supervisor:start_link({local, RegisteredName}, ?MODULE,
                          [SupNamePrefix, Port, HandlerModule,
                           ServerArgs, Options]).

%%-------------------------------------------------------------------------
%% @spec (RegisteredName, SupNamePrefix, Port, HandlerModule, ServerArgs)
%%                                                      -> {ok, Pid}
%%
%% @doc This is equivalent to start_link/6 with an empty set of options.
%% @end
%%-------------------------------------------------------------------------
start_link(RegisteredName, SupNamePrefix, Port, HandlerModule, ServerArgs) ->
    start_link(RegisteredName, SupNamePrefix, Port,
               HandlerModule, ServerArgs, []).

%%%------------------------------------------------------------------------
%%% Supervisor behaviour callbacks
%%%------------------------------------------------------------------------

%% @private
%% @doc This is the socket listener supervisor callback.
init([Name, Port, Module, ServerArgs, Options]) ->
    ConnectionSupName = create_connection_sup_name(Name),

    ConnectionStart = {supervisor, start_link,
                       [{local, ConnectionSupName}, gen_socket_connection_sup,
                        [{connection, [Module, ServerArgs]}]]},

    ListenerSpecs = make_listener_specs(Port, Name, ConnectionSupName,
                                        Module, Options, 1),

    ClientSpec = {ConnectionSupName, ConnectionStart,
                  permanent, infinity, supervisor, [gen_socket_connection_sup]},

    SupFlags = {one_for_one, ?MAX_RESTART, ?MAX_TIME},

    {ok, {SupFlags, [ClientSpec | ListenerSpecs]}}.


%%----------------------------------------------------------------------
%% Internal functions
%%----------------------------------------------------------------------

create_name(Name, Prefix) ->
    list_to_atom(Name ++ "_" ++ Prefix ++ "_sup").

create_connection_sup_name(Name) ->
    create_name(Name, "connection").

make_listener_spec(Port, Name, ConnectionSupName, Module, Options, Count) ->
    Suffix = "listener" ++ integer_to_list(Count),
    ListenerSupName = create_name(Name, Suffix),
    Args = [ListenerSupName, ConnectionSupName, Port, Module, Options],
    ListenerStart = {gen_socket_listener, start_link, Args},
    {ListenerSupName, ListenerStart,
     permanent, 2000, worker, [gen_socket_listener]}.

make_listener_specs(Port, Name, ConnectionSupName, Module, Options, Count)
  when is_integer(Port) ->
    [make_listener_spec(Port, Name, ConnectionSupName, Module, Options, Count)];
make_listener_specs([], _Name, _ConnectionSupName, _Module, _Options, _Count) ->
    [];
make_listener_specs([Port | Ports], Name, ConnectionSupName,
                    Module, Options, Count) ->
    [make_listener_spec(Port, Name, ConnectionSupName,
                        Module, Options, Count) |
     make_listener_specs(Ports, Name, ConnectionSupName,
                         Module, Options, Count + 1)].
