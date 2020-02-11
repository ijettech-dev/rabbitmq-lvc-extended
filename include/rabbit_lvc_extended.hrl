-define(LVC_TABLE, lvc_extended).

-record(cachekey, {exchange, routing_key}).
-record(cached, {key, content}).
