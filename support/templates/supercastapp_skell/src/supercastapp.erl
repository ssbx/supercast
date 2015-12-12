%% @doc The wonderfull {{appid}} application.

-module({{appid}}).
-author("{{author}}").
-export([start/0, stop/0]).

%% supercast channel behaviour
-behaviour(supercast_channel).
-include_lib("supercast/include/supercast.hrl").
-export([join/3,leave/3]).

%% user test
-export([emit/0, emit/2, send/2]).

%% @spec start() -> ok
%% @doc Start the {{appid}} server.
start() ->
    ok = application:start(xmerl),
    ok = application:start(supercast),
    ok = supercast:listen(),
    ChanName = "{{appid}}",
    Perm = #perm_conf{read=["admin"], write=["admin"]},
    Args = [],
    ok = supercast:new_channel(ChanName, ?MODULE, Args, Perm).

stop() ->
    ChanName = "{{appid}}",
    supercast:delete_channel(ChanName),
    init:stop().


%% @spec sync(ChanName::string(), Opts::any(), ClientState::any()) ->
%%      ok | {error, Reason::term()}
%% @doc
%% Wait for reply to the channel_worker process (wich will not emit data
%% because he is himself locking the channel.
%% @end
join("{{appid}}", _Args, _CState) ->
    Pdus = [
        [{<<"from">>, <<"{{appid}}">>}, {<<"value">>, <<"you should be synced now">>}]
        ],
    {ok, Pdus};

join(_, _, _) ->
    {error, "unknown channel"}.

%% @spec leave(Channel, Opts, CState) ->
%%      ok | {error, Reason::string()}
%% @doc
%% Return without waiting reply
%% @end
leave("{{appid}}", _Args, _CState) -> ok;
leave(_Channel, _Opts, _CState) -> {error, "unknown channel"}.


%% @spec emit(Messages::[term()], Perm::any()) -> ok
emit() ->
    Event = [{<<"from">>, <<"{{appid}}">>}, {<<"value">>, <<"Hello event">>}],
    Channel = "{{appid}}",
    supercast:broadcast(Channel, [Event]).
emit(Messages, CustomPerm) ->
    Channel = "{{appid}}",
    supercast:multicast(Channel, Messages, CustomPerm).

%% @spec send_unicast(Messages::[term()], CState) -> ok
send(Messages, CState) ->
    Channel = "{{appid}}",
    supercast:unicast(Channel, Messages, CState).


