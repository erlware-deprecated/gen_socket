%%%-------------------------------------------------------------------
%%% @author Dave Peticolas <dave@krondo.com>
%%% @copyright (C) 2008, Serge Aleynikov
%%% @doc
%%% Generic socket connection supervisor.
%%% @end
%%% Created :  7 Jul 2008 by Dave Peticolas <dave@krondo.com>
%%%-------------------------------------------------------------------
-module(gen_socket_connection_sup).

-behaviour(supervisor).

%% Internal API
-export([start_client/1]).

%% Supervisor callbacks
-export([init/1]).

-define(MAX_RESTART, 5).
-define(MAX_TIME, 60).

%%%===================================================================
%%% API functions
%%%===================================================================

%%-------------------------------------------------------------------------
%% @spec (SupName) -> {ok, Pid}
%% @doc An internal startup function for spawning new connection
%% handling processes.
%% @end
%% @private
%%-------------------------------------------------------------------------
start_client(SupName) ->
    supervisor:start_child(SupName, []).

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a supervisor is started using supervisor:start_link/[2,3],
%% this function is called by the new process to find out about
%% restart strategy, maximum restart frequency and child
%% specifications.
%%
%% @spec init(Args) -> {ok, {SupFlags, [ChildSpec]}} |
%%                     ignore |
%%                     {error, Reason}
%% @end
%%--------------------------------------------------------------------
init([{connection, [Module, Args]}]) ->
    RestartStrategy = simple_one_for_one,

    SupFlags = {RestartStrategy, ?MAX_RESTART, ?MAX_TIME},

    Restart = temporary,
    Shutdown = 2000,
    Type = worker,

    Child = {undefined, {Module, start_link, Args},
             Restart, Shutdown, Type, [Module]},

    {ok, {SupFlags, [Child]}}.
