-module(rabbit_lvc_extended).
-include_lib("rabbit_common/include/rabbit.hrl").
-include_lib("rabbit/include/amqqueue.hrl").
-include("rabbit_lvc_extended.hrl").

-export([setup_schema/0, disable_plugin/0]).
-export([cache_last/3, delete_exchange/1, deliver_to_exchange/2, get_for_exchange/1, get_for_exchange/2,
  cache_incoming/2, deliver_cache/2]).

-rabbit_boot_step({?MODULE,
                   [{description, "last-value cache extended exchange types"},
                    {mfa, {rabbit_lvc_extended, setup_schema, []}},
                    {mfa, {rabbit_registry, register, [exchange, <<"x-lvc-fanout">>, rabbit_exchange_type_lvc_fanout]}},
                    {mfa, {rabbit_registry, register, [exchange, <<"x-lvc-topic">>, rabbit_exchange_type_lvc_topic]}},
                    {cleanup, {?MODULE, disable_plugin, []}},
                    {requires, rabbit_registry},
                    {enables, recovery}]}).

%% private

setup_schema() ->
    mnesia:create_table(?LVC_TABLE,
                        [{attributes, record_info(fields, cached)},
                         {record_name, cached},
                         {type, ordered_set},
                         {disc_copies, [node()]}]),
    mnesia:wait_for_tables([?LVC_TABLE], 30000),
    ok.


disable_plugin() ->
    rabbit_registry:unregister(exchange, <<"x-lvc-fanout">>),
    rabbit_registry:unregister(exchange, <<"x-lvc-topic">>),
    mnesia:delete_table(?LVC_TABLE),
    ok.

cache_last(Name, Keys, Msg) when is_list(Keys) ->
  [ cache_last(Name, K, Msg) || K <- Keys ];
cache_last(Name, RoutingKey, Msg) ->
  Key = #cachekey{exchange = Name, routing_key = RoutingKey},
  _W = mnesia:write(?LVC_TABLE,
    #cached{ key = Key, content = Msg },
    write),
  rabbit_log:info("cached value for ~p - ~p", [Key, _W]),
  _W.

delete_exchange(Name) ->
  [mnesia:delete(?LVC_TABLE, K, write) ||
    #cached{ key = K } <-
      mnesia:match_object(?LVC_TABLE,
        #cached{key = #cachekey{
          exchange = Name, _ = '_' },
          _ = '_'}, write)],
  ok.

deliver_to_exchange(E = #exchange{}, Msg = #basic_message{}) ->
  Delivery = rabbit_basic:delivery(false, false, Msg, undefined),
  Qs = rabbit_amqqueue:lookup(rabbit_exchange:route(E, Delivery)),
  rabbit_amqqueue:deliver(Qs, Delivery),
  ok.

%%get_for_exchange(Name, RoutingKey, DestinationName) ->
%%  ExchangeMatches = get_for_exchange(Name),
%%%%  Words = rabbit_exchange_type_topic:split_topic_key(RoutingKey),
%%%%  Routes = mnesia:async_dirty(fun rabbit_exchange_type_topic:trie_match/2, [Name, Words]),
%%  Destination = [case Dest of
%%                   { queue = Q } -> Q;
%%                   { exchange = X } -> X
%%                 end || Dest <-
%%                 rabbit_exchange_type_topic:route(#exchange{name = Name},
%%                                                  #delivery{message = #basic_message{ routing_keys = [RoutingKey] }})],
%%  rabbit_log:info("filtering matched destinations ~p", [Destination]),
%%%%  Matches = lists:filter(
%%%%    fun( #cached{ key = #cachekey{ routing_key = RK } } ) ->
%%%%      lists:member(RK, Routes)
%%%%    end,
%%%%    ExchangeMatches),
%%
%%  rabbit_log:info("filtered ~p messages for ~p: ~P", [length(Matches), RoutingKey, Matches, 7]),
%%  Matches.

get_for_exchange(Name, Destination) ->
%%  Matches = [
%%    begin
%%      RTs = rabbit_exchange_type_topic:route(#exchange{name = Name},
%%                                             #delivery{message = Msg}),
%%
%%    end || C = #cached{ content = Msg } <- get_for_exchange(Name)
%%  ],
  Matches = lists:filter(
    fun( #cached{ content = Msg } ) ->
      RTs = rabbit_exchange_type_topic:route(#exchange{name = Name},
                                             #delivery{message = Msg}),
      rabbit_log:info("message destinations ~p, message ~P", [RTs, Msg, 7]),
      lists:member(Destination, RTs)
    end,
    get_for_exchange(Name)
  ),
  rabbit_log:info("filtered ~p messages for ~p: ~P", [length(Matches), Destination, Matches, 10]),
  Matches.

get_for_exchange(Name) ->
  Matches = mnesia:dirty_match_object(?LVC_TABLE, #cached{ key = #cachekey{ exchange=Name, _ = '_' }, _ = '_' }),
  rabbit_log:info("matched ~p messages for ~p: ~P", [length(Matches), Name, Matches, 10]),
  Matches.

cache_incoming(Name, Msg) ->
  #basic_message{routing_keys = RKs} = Msg,
  Keys = case RKs of
           CC when is_list(CC) -> CC;
           To                 -> [To]
         end,
  rabbit_misc:execute_mnesia_transaction(
    fun () ->
      rabbit_lvc_extended:cache_last(Name, Keys, Msg)
    end).

deliver_cache(DestinationName, FxCache) ->
  case rabbit_amqqueue:lookup(DestinationName) of
    {error, not_found} ->

      case rabbit_exchange:lookup(DestinationName) of
        {error, not_found} ->
          rabbit_misc:protocol_error(
            internal_error,
            "could not find destination '~s'",
            [DestinationName]);

        {ok, E = #exchange{}} ->
          [ rabbit_lvc_extended:deliver_to_exchange(E, Msg) ||
            #cached{ content = Msg } <- FxCache()
          ]
      end;


    {ok, Q} when ?is_amqqueue(Q) ->
      [ rabbit_amqqueue:deliver([Q], rabbit_basic:delivery(false, false, Msg, undefined)) ||
        #cached{ content = Msg } <- FxCache()
      ]
  end,
  ok.
