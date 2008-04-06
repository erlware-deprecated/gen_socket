%%%-------------------------------------------------------------------
%%% @author Serge Aleynikov <saleyn@gmail.com>
%%% @copyright (C) 2007, 2008, Serge Aleynikov
%%% @doc Generic Socket listener supervisor. See:
%%%      [http://www.trapexit.org/index.php/Building_a_Non-blocking_TCP_server_using_OTP_principles]
%%%
%%% <pre>
%%%    Here is how to add this server to a supervision tree:
%%%
%%%    init([]) ->
%%%        % Socket Server supervisor specification
%%%        SupSpec =
%%%            gen_socket_listener_sup:get_supervisor_spec(
%%%                _NamePrefix    = "myserver",
%%%                _ListenPort    = 9999,
%%%                _HandlerModule = client_handling_module,
%%%                _Args          = [MsgDecoder, MsgHandler]
%%%            ),
%%%
%%%        {ok, {_SupFlags = {one_for_one, 3, 60}, [SupSpec]} }.
%%% </pre>
%%% @end
%%% Created 2007-07-14
%%%-------------------------------------------------------------------
-module(gen_socket_listener_sup).
-author('saleyn@gmail.com').

-behaviour(supervisor).

%% External API
-export([start_link/5, get_supervisor_spec/4]).

%% Internal API
-export([start_client/1]).

%% Supervisor callbacks
-export([init/1]).

-define(MAX_RESTART,    5).
-define(MAX_TIME,      60).

%%-------------------------------------------------------------------------
%% @spec (SupNamePrefix, Port, HandlerModule, ServerArgs) -> SupSpec::tuple()
%%         SupNamePrefix  = string()
%%         Port           = integer()
%%         HandlerModule  = atom()
%%         ServerArgs     = [ term() ]
%% @doc Generates the supervisor specification that can be used by the
%%      application top supervisor's init/1 callback function that
%%      wants to link socket server under its supervision tree.
%%      `SupNamePrefix' is the perfix used for naming listener supervisor
%%      (SupNamePrefix ++ "listener_sup") and connection manager supervisor
%%      (SupNamePrefix ++ "connection_sup").
%%      `HandlerModule' is the module implementing a user protocol process,
%%        whose `start_link' function should accept `ServerArgs'.
%% @end
%%-------------------------------------------------------------------------
get_supervisor_spec(SupNamePrefix, Port, HandlerModule, HandlerModuleArgs) ->
    SupName      = create_name(SupNamePrefix, "socket_server"),
    ListenerArgs = [SupName, SupNamePrefix, Port, HandlerModule, HandlerModuleArgs],
    % Socket Listener
    {   SupName,                                       % Id       = internal id
        {gen_socket_listener_sup, start_link, ListenerArgs}, % StartFun = {M, F, A}
        permanent,                                     % Restart  = permanent | transient | temporary
        2000,                                          % Shutdown = brutal_kill | int() >= 0 | infinity
        worker,                                        % Type     = worker | supervisor
        [gen_socket_listener_sup]                      % Modules  = [Module] | dynamic
    }.

%%-------------------------------------------------------------------------
%% @spec (RegisteredName, SupNamePrefix, Port, HandlerModule, ServerArgs) -> {ok, Pid}
%%         RegisteredName = string()
%%         SupNamePrefix  = atom()
%%         Port           = integer()
%%         HandlerModule  = atom()
%%         ServerArgs     = [ term() ]
%%
%% @doc To be called by the top-level application supervisor to
%% start socket server listener.
%% `RegisteredName' is the registered name of the socket server's supervisor.
%% @see get_supervisor_spec/4
%% @end
%%-------------------------------------------------------------------------
start_link(RegisteredName, SupNamePrefix, Port, HandlerModule, ServerArgs)
  when is_atom(RegisteredName), is_list(SupNamePrefix) ->
    supervisor:start_link({local, RegisteredName}, ?MODULE, [SupNamePrefix, Port, HandlerModule, ServerArgs]).

%%-------------------------------------------------------------------------
%% @spec (SupName) -> {ok, Pid}
%% @doc An internal startup function for spawning new client connection
%% handling processes.
%% To be called by the gen_socket_listener process.
%% @end
%% @private
%%-------------------------------------------------------------------------
start_client(SupName) ->
    supervisor:start_child(SupName, []).

%%%------------------------------------------------------------------------
%%% Supervisor behaviour callbacks
%%%------------------------------------------------------------------------

%% @private
init([Name, Port, Module, ServerArgs]) ->
    ListenerSupName   = create_name(Name, "listener"),
    ConnectionSupName = create_name(Name, "connection"),
    Args = [ListenerSupName, ConnectionSupName, Port, Module],
    {ok,
        {_SupFlags = {one_for_one, ?MAX_RESTART, ?MAX_TIME},
            [
              % Socket Listener
              {   ListenerSupName,                         % Id       = internal id
                  {gen_socket_listener,start_link,Args},   % StartFun = {M, F, A}
                  permanent,                               % Restart  = permanent | transient | temporary
                  2000,                                    % Shutdown = brutal_kill | int() >= 0 | infinity
                  worker,                                  % Type     = worker | supervisor
                  [gen_socket_listener]                    % Modules  = [Module] | dynamic
              },
              % Client instance supervisor
              {   ConnectionSupName,
                  {supervisor,start_link,[{local, ConnectionSupName}, ?MODULE, [{connection, [Module, ServerArgs]}]]},
                  permanent,                               % Restart  = permanent | transient | temporary
                  infinity,                                % Shutdown = brutal_kill | int() >= 0 | infinity
                  supervisor,                              % Type     = worker | supervisor
                  []                                       % Modules  = [Module] | dynamic
              }
            ]
        }
    };

%% This one is called by the supervisor spec above.
init([{connection, [Module, Args]}]) ->
    {ok,
        {_SupFlags = {simple_one_for_one, ?MAX_RESTART, ?MAX_TIME},
            [
              % Socket Client
              {   undefined,                               % Id       = internal id
                  {Module,start_link,Args},                % StartFun = {M, F, A}
                  temporary,                               % Restart  = permanent | transient | temporary
                  2000,                                    % Shutdown = brutal_kill | int() >= 0 | infinity
                  worker,                                  % Type     = worker | supervisor
                  []                                       % Modules  = [Module] | dynamic
              }
            ]
        }
    }.

%%----------------------------------------------------------------------
%% Internal functions
%%----------------------------------------------------------------------

create_name(Name, Prefix) ->
    list_to_atom(Name ++ "_" ++ Prefix ++ "_sup").
