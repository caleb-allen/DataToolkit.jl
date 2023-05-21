module Store

using DataToolkitBase
using BaseDirs
using CRC32c
using Dates
using TOML
using UUIDs
using Serialization

import ..DataToolkitCommon: should_log_event

const INVENTORY_FILENAME = "Inventory.toml"
const USER_STORE = BaseDirs.User.cache(BaseDirs.Project("Data Store"), create=true)
const USER_INVENTORY = joinpath(USER_STORE, INVENTORY_FILENAME)

include("types.jl")
include("rhash.jl")
include("inventory.jl")
include("storage.jl")
include("plugins.jl")

include("repl.jl")

function __init__()
    @dataplugin STORE_PLUGIN :default
    @dataplugin CACHE_PLUGIN
    let pos = searchsorted(REPL_CMDS, STORE_REPL_CMD, by=c -> DataToolkitBase.natkeygen(c.trigger))
        splice!(REPL_CMDS, pos, (STORE_REPL_CMD,))
    end
    push!(INVENTORIES, load_inventory(USER_INVENTORY))
    atexit() do
        for inv in INVENTORIES
            hours_since = (now() - inv.last_gc).value / (1000 * 60 * 60)
            if inv.config.auto_gc > 0 && hours_since > inv.config.auto_gc
                garbage_collect!(inv; log=false, trimmsg=true)
            end
        end
    end
end

end
