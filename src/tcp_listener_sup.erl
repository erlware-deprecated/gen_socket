%%%------------------------------------------------------------------------
%%% File: $Id$
%%%------------------------------------------------------------------------
%%% @doc Generic TCP listener supervisor. See:
%%%      [http://www.trapexit.org/index.php/Building_a_Non-blocking_TCP_server_using_OTP_principles]
%%%
%%% <pre>
%%%    Here is how to add this server to a supervision tree:
%%%
%%%    init([]) ->
%%%        % TCP Server supervisor specification
%%%        TcpSupSpec =
%%%            tcp_listener_sup:get_supervisor_spec(
%%%                _NamePrefix    = "myserver",
%%%                _TcpListenPort = 9999,
%%%                _TcpProtoFsm   = client_handling_fsm,
%%%                _Args          = [MsgDecoder, MsgHandler]
%%%            ),
%%%
%%%        {ok, {_SupFlags = {one_for_one, 3, 60}, [TcpSupSpec]} }.
%%% </pre>
%%% @author  Serge Aleynikov <saleyn@gmail.com>
%%% @version $Rev$
%%%          $Date$
%%% @end
%%%------------------------------------------------------------------------
%%% Created 2007-07-14
%%%------------------------------------------------------------------------
%%% Copyright (c) 2007 Serge Aleynikov
%%%
%%% Permission is hereby granted, free of charge, to any person obtaining
%%% a copy of this software and associated documentation files
%%% (the "Software"), to deal in the Software without restriction,
%%% including without limitation the rights to use, copy,
%%% modify, merge, publish, distribute, sublicense, and/or sell copies of
%%% the Software, and to permit persons to whom the Software is furnished
%%% to do so, subject to the following conditions:
%%%
%%% The above copyright notice and this permission notice shall be
%%% included in all copies or substantial portions of the Software.
%%%
%%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
%%% EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
%%% OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
%%% NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
%%% BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
%%% ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
%%% CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%%% THE SOFTWARE.
%%%------------------------------------------------------------------------
-module(tcp_listener_sup).
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
%% @spec (SupNamePrefix, Port, HandlerModule, ServerArgs) -> TcpSupSpec::tuple()
%%         SupNamePrefix  = string()
%%         Port           = integer()
%%         HandlerModule  = atom()
%%         ServerArgs     = [ term() ]
%% @doc Generates the supervisor specification that can be used by the
%%      application top supervisor's init/1 callback function that
%%      wants to link TCP server under its supervision tree.
%%      `SupNamePrefix' is the perfix used for naming listener supervisor
%%      (SupNamePrefix ++ "listener_sup") and connection manager supervisor
%%      (SupNamePrefix ++ "connection_sup").
%%      `HandlerModule' is the module implementing a user protocol FSM, whose `start_link'
%%      function should accept `ServerArgs'.
%% @end
%%-------------------------------------------------------------------------
get_supervisor_spec(TcpSupNamePrefix, Port, FsmHandlerModule, FsmHandlerModuleArgs) ->
    TcpSupName      = create_name(TcpSupNamePrefix, "tcp_server"),
    TcpListenerArgs = [TcpSupName, TcpSupNamePrefix, Port, FsmHandlerModule, FsmHandlerModuleArgs],
    % TCP Listener
    {   TcpSupName,                                    % Id       = internal id
        {tcp_listener_sup,start_link,TcpListenerArgs}, % StartFun = {M, F, A}
        permanent,                                     % Restart  = permanent | transient | temporary
        2000,                                          % Shutdown = brutal_kill | int() >= 0 | infinity
        worker,                                        % Type     = worker | supervisor
        [tcp_listener_sup]                             % Modules  = [Module] | dynamic
    }.

%%-------------------------------------------------------------------------
%% @spec (RegisteredName, SupNamePrefix, Port, HandlerModule, ServerArgs) -> {ok, Pid}
%%         RegisteredName = string()
%%         SupNamePrefix  = atom()
%%         Port           = integer()
%%         HandlerModule  = atom()
%%         ServerArgs     = [ term() ]
%%
%% @doc To be called by the top-level application supervisor to start TCP server listener.
%%      `RegisteredName' is the registered name of the TCP server's supervisor.
%% @see get_supervisor_spec/4
%% @end
%%-------------------------------------------------------------------------
start_link(RegisteredName, SupNamePrefix, Port, HandlerModule, ServerArgs)
  when is_atom(RegisteredName), is_list(SupNamePrefix) ->
    supervisor:start_link({local, RegisteredName}, ?MODULE, [SupNamePrefix, Port, HandlerModule, ServerArgs]).

%%-------------------------------------------------------------------------
%% @spec (SupName) -> {ok, Pid}
%% @doc An internal startup function for spawning new client connection handling FSMs.
%% To be called by the tcp_listener process.
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
              % TCP Listener
              {   ListenerSupName,                         % Id       = internal id
                  {tcp_listener,start_link,Args},          % StartFun = {M, F, A}
                  permanent,                               % Restart  = permanent | transient | temporary
                  2000,                                    % Shutdown = brutal_kill | int() >= 0 | infinity
                  worker,                                  % Type     = worker | supervisor
                  [tcp_listener]                           % Modules  = [Module] | dynamic
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
              % TCP Client
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
