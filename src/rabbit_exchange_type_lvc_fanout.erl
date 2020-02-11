-module(rabbit_exchange_type_lvc_fanout).
-include_lib("rabbit_common/include/rabbit.hrl").
-include_lib("rabbit/include/amqqueue.hrl").
-include("rabbit_lvc_extended.hrl").

-behaviour(rabbit_exchange_type).

-export([description/0, serialise_events/0, route/2]).
-export([validate/1, validate_binding/2,
         create/2, recover/2, delete/3, policy_changed/2,
         add_binding/3, remove_bindings/3, assert_args_equivalence/2]).
-export([info/1, info/2]).

info(_X) -> [].
info(_X, _) -> [].

description() ->
    [{name, <<"x-lvc-fanout">>},
     {description, <<"Last-value cache fanout exchange.">>}].

serialise_events() -> false.

route(Exchange = #exchange{name = Name},
      Delivery = #delivery{message = Msg}) ->
    rabbit_lvc_extended:cache_incoming(Name, Msg),
    rabbit_exchange_type_fanout:route(Exchange, Delivery).

validate(_X) -> ok.
validate_binding(_X, _B) -> ok.
create(_Tx, _X) -> ok.
recover(_X, _Bs) -> ok.

delete(transaction, #exchange{ name = Name }, _Bs) ->
    rabbit_lvc_extended:delete_exchange(Name),
    ok;
delete(_Tx, _X, _Bs) ->
	ok.

policy_changed(_X1, _X2) -> ok.

add_binding(none, #exchange{ name = XName },
                  #binding{ destination = DestinationName }) ->
%%    case rabbit_amqqueue:lookup(DestinationName) of
%%        {error, not_found} ->
%%
%%            case rabbit_exchange:lookup(DestinationName) of
%%              {error, not_found} ->
%%                rabbit_misc:protocol_error(
%%                  internal_error,
%%                  "could not find destination '~s'",
%%                  [DestinationName]);
%%
%%              {ok, E = #exchange{}} ->
%%                [ rabbit_lvc_extended:deliver_to_exchange(E, Msg) ||
%%                  #cached{ content = Msg } <- rabbit_lvc_extended:get_for_exchange(XName)
%%                ]
%%            end;
%%
%%
%%        {ok, Q} when ?is_amqqueue(Q) ->
%%            [ rabbit_amqqueue:deliver([Q], rabbit_basic:delivery(false, false, Msg, undefined)) ||
%%              #cached{ content = Msg } <- rabbit_lvc_extended:get_for_exchange(XName)
%%              ]
%%    end,
%%    ok;
    rabbit_lvc_extended:deliver_cache(DestinationName,
      fun () ->
        rabbit_lvc_extended:get_for_exchange(XName)
      end);
add_binding(_Tx, _X, _B) ->
    ok.

remove_bindings(_Tx, _X, _Bs) -> ok.

assert_args_equivalence(X, Args) ->
    rabbit_exchange_type_fanout:assert_args_equivalence(X, Args).
