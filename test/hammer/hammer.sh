#!/bin/sh
mix compile.protocols
elixir -pa _build/$MIX_ENV/consolidated -S mix run `dirname $0`/hammer.exs
