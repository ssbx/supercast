%% -----------------------------------------------------------------------------
%% Supercast Copyright (c) 2012-2015
%% Sebastien Serre <ssbx@supercastframework.org> All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%% -----------------------------------------------------------------------------

%%%-----------------------------------------------------------------------------
%%% @author Sebastien Serre <ssbx@supercastframework.org>
%%% @copyright (C) 2015, Sebastien Serre
%%% @private
%%% @doc
%%% This module is used to subscribe and keep synchronisation between a channel
%%% and his clients. It is started on demand and shuted down when there are no
%%% more clients to handle.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(supercast_relay).
-behaviour(gen_server).
-include("supercast.hrl").

%% API
-export([
    start_link/1,
    unicast/3,
    multicast/3,
    subscribe/3,
    subscribe_ack/4,
    unsubscribe/1,
    unsubscribe/3,
    unsubscribe_ack/4]).

%% called from supercast module
-export([delete/1]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-record(state, {
    chan_name,
    clients = []
}).

%%%=============================================================================
%%% API
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @private
%% @doc
%% Starts the server
%%
%% @end
%%------------------------------------------------------------------------------
-spec(start_link(Name :: string()) ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(Name) ->
    gen_server:start_link({via, supercast, Name}, ?MODULE, Name, []).

%%------------------------------------------------------------------------------
%% @private
%% @doc
%% Called from the endpoint
%%
%% @end
%% @TODO possible race condition with ?ETS_CHAN_STATES ???
%%------------------------------------------------------------------------------
-spec(subscribe(CState :: #client_state{}, Channel :: string(),
    QueryId :: integer()) -> ok | error).
subscribe(CState, Channel, QueryId) ->

    %% does the channel exist?
    ?SUPERCAST_LOG_INFO("subscribe", {CState, Channel}),
    case ets:lookup(?ETS_CHAN_STATES, Channel) of

        [] -> %% no
            ?SUPERCAST_LOG_INFO("no channel"),
            error;

        [#chan_state{perm=Perm}] -> %% yes

            %% the client is allowed to connect to the channel?
            {ok, AcctrlMod} = application:get_env(supercast, acctrl_module),
            ?SUPERCAST_LOG_INFO("acctrl", {AcctrlMod, Perm}),
            case AcctrlMod:satisfy(read, [CState], Perm) of

                {ok, []} -> %% no
                    ?SUPERCAST_LOG_INFO("does not satisfy"),
                    error;

                _ ->
                    ?SUPERCAST_LOG_INFO("does satisfy"),

                    %% create relay if it does not exists
                    %% start_child will return {ok,Pid}
                    %% or {error,allready_tarted}
                    supercast_relay_sup:start_relay([Channel]),

                    gen_server:cast({via, supercast, Channel},
                                                {subscribe, CState, QueryId})
                    %% The client side is now waiting for subscribeOk|Err pdu
            end
    end.


%%------------------------------------------------------------------------------
%% @private
%% @doc
%% Unsubscribe the client from all channels.
%%
%% @end
%%------------------------------------------------------------------------------
-spec(unsubscribe(CState :: #client_state{}) -> ok).
unsubscribe(CState) ->
    ?SUPERCAST_LOG_INFO("unsubscribe all", CState),
    Chans = [Name || #chan_state{name=Name} <- ets:tab2list(?ETS_CHAN_STATES)],
    lists:foreach(fun(Chan) ->
        unsubscribe(Chan, CState, undefined)
    end, Chans).


%%------------------------------------------------------------------------------
%% @private
%% @doc
%% Unsubscribe the client from one channels.
%%
%% If QueryId is the atom undefined, this mean that the client unsubscribe to
%% the specified channels because the socket has closed.
%%
%% @end
%%------------------------------------------------------------------------------
-spec(unsubscribe(Channel :: string(), CState :: #client_state{},
    QueryId :: integer() | undefined) -> ok).
unsubscribe(Channel, CState, QueryId) ->
    ?SUPERCAST_LOG_INFO("unsubscribe chan", {Channel, CState}),
    gen_server:cast({via, supercast, Channel}, {unsubscribe, CState, QueryId}).


%%------------------------------------------------------------------------------
%% @doc
%% Subscribe client ack with initial data from the channel.
%%
%% @end
%%------------------------------------------------------------------------------
-spec(subscribe_ack(Channel :: string(), CState :: #client_state{},
    QueryId :: integer(), Pdus :: [supercast_msg()]) -> ok).
subscribe_ack(Channel, CState, QueryId, Pdus) ->
    gen_server:cast({via, supercast, Channel},
                                        {subscribe_ack, CState, QueryId, Pdus}).


%%------------------------------------------------------------------------------
%% @doc
%% Unsubscribe client ack with initial data from the channel.
%%
%% @end
%%------------------------------------------------------------------------------
-spec(unsubscribe_ack(Channel :: string(), CState :: #client_state{},
    QueryId :: integer(), Pdus :: [term()]) -> ok).
unsubscribe_ack(Channel, CState, QueryId, Pdus) ->
    gen_server:cast({via, supercast, Channel},
                                        {unsubscribe_ack, CState, QueryId, Pdus}).


%%------------------------------------------------------------------------------
%% @private
%% @doc
%% Delete a channel.
%%
%% @end
%%------------------------------------------------------------------------------
-spec(delete(Channel :: string()) -> ok).
delete(Channel) ->
    ?SUPERCAST_LOG_INFO("delete channel", Channel),
    gen_server:cast({via, supercast, Channel}, delete).


%%------------------------------------------------------------------------------
%% @private
%% @doc
%% Send messages to multiple clients. If the Perm is set to "default" there will
%% be no filtering. IE: All clients allowed to register to the channel will
%% receive the message.
%%
%% @end
%%------------------------------------------------------------------------------
-spec(multicast(Pid :: pid(), Msgs :: [supercast_msg()],
    Perm :: #perm_conf{} | default) -> ok).
multicast(Pid, Msgs, Perm) ->
    ?SUPERCAST_LOG_INFO("multicast", {Pid,Msgs,Perm}),
    gen_server:cast(Pid, {multicast, Msgs, Perm}).


%%------------------------------------------------------------------------------
%% @private
%% @doc
%% Send messages to multiple clients. If the Perm is set to "default" there will
%% be no filtering. IE: All clients allowed to register to the channel will
%% receive the message.
%%
%% @end
%%------------------------------------------------------------------------------
-spec(unicast(Pid :: pid(), CState :: #client_state{},
        Msgs :: [supercast_msg()]) -> ok).
unicast(Pid, CState, Msgs) ->
    ?SUPERCAST_LOG_INFO("unicast", {Pid,CState, Msgs}),
    gen_server:cast(Pid, {unicast, CState, Msgs}).


%%%=============================================================================
%%% gen_server callbacks
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @private
%% @see gen_server:init/1
%%------------------------------------------------------------------------------
-spec(init(Args :: string()) ->
    {ok, State :: #state{}} | {stop, Reason :: term()}).
init(ChanName) ->
    process_flag(trap_exit, true),
    ?SUPERCAST_LOG_INFO("init channel", ChanName),
    %% @TODO make supercast_relay_control
    case ets:lookup(?ETS_CHAN_STATES, ChanName) of
        [] ->
            ?SUPERCAST_LOG_INFO("channel vanished", ChanName),
            %% channel has vanished
            {stop, "Channel has vanished"};
        _ ->
            ?SUPERCAST_LOG_INFO("channel continue", ChanName),
            %% Now the process can allready have in his queue a cast(delete)
            {ok, #state{chan_name=ChanName}}
    end.


%%------------------------------------------------------------------------------
%% @private
%% @see gen_server:cast/2
%%------------------------------------------------------------------------------
-type(relay_cast_request() ::
        {multicast, Msgs :: [supercast_msg()], default | #perm_conf{}} |
        {unicast, Msgs :: [supercast_msg()], Client :: #client_state{}} |
        {unsubscribe, Client :: #client_state{}, QueryId :: integer()} |
        {unsubscribe_ack, Client :: #client_state{}} |
        {subscribe, Client :: #client_state{}, QueryId :: integer} |
        {subscribe_ack, Client :: #client_state{}, QueryId :: integer(),
            Pdus :: [supercast_msg()]} | delete).
-spec(handle_cast(Request :: relay_cast_request(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_cast({unicast, #client_state{module=Mod} = CState, Msgs},
        #state{clients=Clients} = State) ->
    case lists:member(CState,Clients) of
        true ->
    lists:foreach(fun(M) ->
        Mod:send(CState, M)
    end, Msgs);
        false -> %% it is wrong. Do not send the message.
            ?SUPERCAST_LOG_WARNING(
              "Attempt to send a message to an unsubscribed user",
               {CState, Msgs})
    end,
    {noreply, State};
handle_cast({multicast, Msgs, default},
                        #state{chan_name=_ChanName,clients=Clients} = State) ->
    ?SUPERCAST_LOG_INFO("multicast"),
    multi_send(Clients, Msgs),
    {noreply, State};

handle_cast({multicast, Msgs, Perm},
                        #state{chan_name=_ChanName,clients=Clients} = State) ->
    ?SUPERCAST_LOG_INFO("multicast"),
    {ok, Acctrl} = application:get_env(supercast, acctrl_module),
    {ok, Clients2} = Acctrl:satisfy(read, Clients, Perm),
    multi_send(Clients2, Msgs),
    {noreply, State};

handle_cast({unicast, Msgs, #client_state{module=Mod} = To},
                                        #state{chan_name=_ChanName} = State) ->
    ?SUPERCAST_LOG_INFO("unicast"),
    lists:foreach(fun(P) ->
        Mod:send(To, P)
    end, Msgs),
    {noreply, State};

handle_cast({unsubscribe_ack, #client_state{module=Mod} = CState,
    QueryId, Pdus}, #state{chan_name=ChanName, clients=Clients} = State) ->
    ?SUPERCAST_LOG_INFO("unsubscribe_ack"),

    case QueryId of
        undefined -> %% unsubscribed because the socket has closed.
            ok;
        _ ->
            OkUnsub = supercast_endpoint:pdu(unsubscribeOk, {QueryId, ChanName}),
            lists:foreach(fun(P) ->
                Mod:send(CState, P)
            end, lists:append(Pdus, [OkUnsub]))
    end,

    case lists:delete(CState, Clients) of
        [] -> %% will terminate in 10 seconds if no more clients are subscribing
            {noreply, State#state{clients=[]}, 10000};
        Other ->
            {noreply, State#state{clients=Other}}
    end;

handle_cast({unsubscribe, #client_state{module=Mod} = CState, QueryId},
    #state{clients=Clients,chan_name=Name} = State) ->
    ?SUPERCAST_LOG_INFO("unsubscribe"),
    case lists:member(CState, Clients) of

        false -> %% not a subscribed client
            %% if queryid is an integer reply unsubscribeOk
            case QueryId of

                undefined -> %% nothing to do
                    ok;

                _ -> %% send a message to the client
                    OkUnsub = supercast_endpoint:pdu(
                                                unsubscribeOk, {QueryId, Name}),
                    Mod:send(CState, OkUnsub)
            end;

        true -> %% is a member
            ?SUPERCAST_LOG_INFO("unsubscribe", Name),
            case ets:lookup(?ETS_CHAN_STATES, Name) of
                [#chan_state{module=CMod,args=Args}] ->
                     erlang:spawn(fun() ->
                        Ref = {Name, CState, QueryId},
                        CMod:leave(Name, Args, CState, Ref)
                    end);
                _ ->
                    OkUnsub = supercast_endpoint:pdu(
                                                unsubscribeOk, {QueryId, Name}),
                    Mod:send(CState, OkUnsub)
            end
    end,
    {noreply, State};


handle_cast({subscribe_ack, #client_state{module=Mod} = CState,
    QueryId, Pdus}, #state{chan_name=ChanName, clients=Clients} = State) ->

    OkPdu = supercast_endpoint:pdu(subscribeOk, {QueryId, ChanName}),
    lists:foreach(fun(P) -> Mod:send(CState, P) end, [OkPdu | Pdus]),
    {noreply, State#state{clients=[CState|Clients]}};

handle_cast({subscribe, QueryId, #client_state{module=Mod} = CState},
                #state{chan_name=ChanName,clients=Clients} = State) ->

    ?SUPERCAST_LOG_INFO("subscribe cast"),
    case lists:member(CState, Clients) of

        false ->
            ?SUPERCAST_LOG_INFO("false"),

            case ets:lookup(?ETS_CHAN_STATES, ChanName) of

                [#chan_state{module=CMod,args=Args}] ->
                    ?SUPERCAST_LOG_INFO("found in chan_states"),

                    erlang:spawn(fun() ->
                        Ref = {ChanName, CState, QueryId},
                        CMod:join(ChanName, Args, CState, Ref)
                    end);

                _Other ->
                    ?SUPERCAST_LOG_INFO("other", _Other),
                    ErrPdu = supercast_endpoint:pdu(
                                            subscribeErr, {QueryId, ChanName}),
                    Mod:send(CState, ErrPdu)

            end; %% end ets:lookup

        true -> %% allready registered
            ?SUPERCAST_LOG_INFO("true"),
            OkPdu = supercast_endpoint:pdu(subscribeOk, {QueryId, ChanName}),
            Mod:send(CState, OkPdu)

    end, %% end lists:member
    {noreply, State};

handle_cast(delete, #state{clients=Clients,chan_name=Name}) ->
    ?SUPERCAST_LOG_INFO("delete channel"),
    Pdu = ?ENCODER:encode(pdu(channelDeleted, Name)),
    lists:foreach(fun(#client_state{module=Mod} = C) ->
        Mod:raw_send(C, Pdu)
    end, Clients),
    {stop, {"Channel deleted", Name}};

handle_cast(_Cast, State) ->
    ?SUPERCAST_LOG_INFO("unknown cast", _Cast),
    {noreply, State}.


%%------------------------------------------------------------------------------
%% @private
%% @see gen_server:call/3
%%------------------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
    {noreply, NewState :: #state{}}).
handle_call(_Request, _From, State) -> {noreply, State}.


%%------------------------------------------------------------------------------
%% @private
%% @see gen_server:handle_info/3
%%------------------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_info(timeout, #state{clients=[]}) ->
    {stop, normal, #state{}};
handle_info(_Info, State) ->
    {noreply, State}.


%%------------------------------------------------------------------------------
%% @private
%% @see gen_server:code_change/3
%%------------------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) -> term()).
code_change(_OldVsn, State, _Extra) -> {ok, State}.


%%------------------------------------------------------------------------------
%% @private
%% @see gen_server:terminate/2
%% @see supercast:unregister_name/1
%% @doc
%% The process trap exists. Will unregister the name with
%% supercast:unregister_name/1
%%
%% @end
%%------------------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, #state{chan_name=Name}) ->
    ?SUPERCAST_LOG_INFO("terminate relay", _Reason),
    supercast:unregister_name(Name),
    ok.


%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @private
%% @doc
%% Generate a channelDelete pdu
%%
%% @end
%%------------------------------------------------------------------------------
-spec(pdu(channDeleted, Channel :: string()) -> supercast_msg()).
pdu(channelDeleted, Channel) ->
        [
            {<<"from">>, <<"supercast">>},
            {<<"type">>, <<"channelDeleted">>},
            {<<"value">>, [
                {<<"channel">>, list_to_binary(Channel)}
            ]}
        ].


%%------------------------------------------------------------------------------
%% @private
%% @doc
%% Helper to send multiple pdus to multipe clients.
%%
%% @end
%%------------------------------------------------------------------------------
-spec(multi_send(Clients :: [#client_state{}],
    Messages :: [supercast_msg()]) -> ok).
multi_send(Clients, Msgs) ->
    lists:foreach(fun(Message) ->
        Pdu = ?ENCODER:encode(Message),
        lists:foreach(fun(#client_state{module=Mod} = Client) ->
            Mod:raw_send(Client, Pdu)
        end, Clients)
    end, Msgs).
