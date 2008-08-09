{application, gen_socket,
 [{description, "A library for generic socket servers (TCP and Unix)"},
  {vsn, "0.1.2"},
  {modules, [gen_socket_sup, gen_socket_connection_sup, gen_socket_listener]},
  {registered, []},
  {applications, [kernel, stdlib]},
  {start_phases, []}
 ]
}.
