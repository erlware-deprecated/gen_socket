%%%-------------------------------------------------------------------
%%% @author Dave Peticolas <dave@krondo.com>
%%% @copyright (C) 2008, Dave Peticolas
%%% @doc
%%% This is an example of a simple echo server using gen_socket.
%%%
%%% To run this demo, compile this file and start an erlang
%%% shell. Make sure the main gen_socket modules and this
%%% module are on the code path and run echo:start_demo().
%%% This will create an echo server on port 9999 to which
%%% you can connect using, for example, telnet.
%%% @end
%%% Created : 12 Apr 2008 by Dave Peticolas <dave@krondo.com>
%%%-------------------------------------------------------------------
-module(echo).

% Both these functions must be exported
% by any socket handling module.
-export([start_demo/0, start_link/0, set_socket/2]).


% Start the echo server demo on port 9999. This returns {ok, Pid}
% where Pid is the socket listener supervisor. The gen_socket server
% is implemented with two supervisors, one to manage the server which
% accepts new connections on the listening socket, and one to manage
% and create servers to handle each new connection.
%
% The servers which manage the connection are implemented by client
% code. This module implements a line-based echo server.
%
% In a real application, The socket listener supervisor
% would be started by a higher-level supervisor with a
% spec created by gen_socket_listener_sup:get_supervisor_spec.
%
% @spec start_demo() -> {ok, Pid}
start_demo() ->
    gen_socket_listener_sup:start_link(echo, "echo", 9999, echo, []).

% This is called by the connection supervisor when the
% gen_socket_listener_sup:start_client function is called.
% It starts a new server for a single connection.
%
% @spec start_link() -> {ok, Pid}
start_link() ->
    {ok, spawn_link(fun server/0)}.

% This is called by the gen_socket_listener process to
% pass the socket that a new connection process will be
% responsible for.
%
% @set_socket(Pid, Socket) -> void
set_socket(Pid, Socket) ->
    Pid ! {socket_ready, Socket}.

% This is the main server loop for the echo example. The socket_ready
% message tells the server which socket it is responsible for. The tcp
% message passes incoming data to the server and tcp_closed is received
% when the socket is closed by the client.
server() ->
    receive
        {socket_ready, Socket} ->
            io:format("~p made connection: ~p~n", [self(), Socket]),
            inet:setopts(Socket, [{active, once}, {packet, line}, binary]),
            server();
        {tcp, Socket, <<"quit\n">>} ->
            io:format("~p got quit~n", [self()]),
            gen_tcp:close(Socket);
        {tcp, Socket, Data} ->
            io:format("~p got data: ~p~n", [self(), Data]),
            inet:setopts(Socket, [{active, once}]),
            gen_tcp:send(Socket, Data),
            server();
        {tcp_closed, Socket} ->
            io:format("~p socket is closed: ~p~n", [self(), Socket])
    end.
