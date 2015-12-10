-module(supercast_reg_test).
-compile(export_all).

common_test() ->
    %% read the sys.config file and set_env
    PDir = filename:absname(".."),
    SFile = filename:join(PDir, "sys.config"),
    {ok,[[{supercast,SContent}]]} = file:consult(SFile),
    set_env(SContent),
    supercast:start(),

    Pid1 = spawn(fun() -> receive _ -> ok end end),
    Pid2 = spawn(fun() -> receive _ -> ok end end),
    yes  = supercast_reg:register_name("test_name", Pid1),
    no   = supercast_reg:register_name("test_name", Pid2),
    Pid1 = supercast_reg:whereis_name("test_name"),
    Pid1 = supercast_reg:send("test_name", shutdown),
    timer:sleep(100),
    undefined = supercast_reg:whereis_name("test_name"),
    yes  = supercast_reg:register_name("test_name", Pid2),
    Pid2 = supercast_reg:whereis_name("test_name"),
    "test_name" = supercast_reg:unregister_name("test_name"),
    undefined = supercast_reg:whereis_name("test_name"),
    true = erlang:is_process_alive(Pid2),
    false = erlang:is_process_alive(Pid1),
    ok = supercast:stop().



set_env([]) -> ok;
set_env([{Key,Value}|T]) ->
    application:set_env(supercast, Key, Value),
    set_env(T).
