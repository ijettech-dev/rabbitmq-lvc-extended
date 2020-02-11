-module(rabbit_exchange_type_lvc_topic).
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
  [{name, <<"x-lvc-topic">>},
    {description, <<"Last-value cache topic exchange.">>}].

serialise_events() -> false.

route(Exchange = #exchange{name = Name},
    Delivery = #delivery{message = Msg}) ->
  rabbit_lvc_extended:cache_incoming(Name, Msg),
  rabbit_exchange_type_topic:route(Exchange, Delivery).

validate(_X) -> ok.
validate_binding(_X, _B) -> ok.
create(_Tx, _X) -> ok.
recover(_X, _Bs) -> ok.

delete(transaction, _X = #exchange{ name = Name }, _Bs) ->
  rabbit_lvc_extended:delete_exchange(Name),
  rabbit_exchange_type_topic:delete(transaction, _X, _Bs);
delete(_Tx, _X, _Bs) ->
  rabbit_exchange_type_topic:delete(_Tx, _X, _Bs).

policy_changed(_X1, _X2) -> ok.

add_binding(none, _X = #exchange{ name = XName },
    _B = #binding{ destination = Destination }) ->
  rabbit_exchange_type_topic:add_binding(none, _X, _B),
  rabbit_lvc_extended:deliver_cache(Destination,
    fun () ->
      rabbit_lvc_extended:get_for_exchange(XName, Destination)
    end),
  ok;
add_binding(_Tx, _X, _B) ->
  rabbit_exchange_type_topic:add_binding(_Tx, _X, _B).

remove_bindings(_Tx, _X, _Bs) ->
  rabbit_exchange_type_topic:remove_bindings(_Tx, _X, _Bs).

assert_args_equivalence(X, Args) ->
  rabbit_exchange_type_topic:assert_args_equivalence(X, Args).
