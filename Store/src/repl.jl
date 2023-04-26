import DataToolkitBase: allcompletions

function repl_config_get(input::AbstractString)
    update_inventory!()
    value_sets = [(:auto_gc, "hours"),
                  (:max_age, "days"),
                  (:max_size, join ∘ humansize),
                  (:recency_beta, "")]
    if !isempty(input)
        filter!((v, _)::Tuple -> String(v) == input, value_sets)
        if isempty(value_sets)
            printstyled(" ! ", color=:red, bold=true)
            println("'$input' is not a valid configuration parameter")
            return
        end
    end
    for (param, printer) in value_sets
        printstyled("  ", param, color=:cyan)
        value = getproperty(INVENTORY.config, param)
        default = getproperty(DEFAULT_INVENTORY_CONFIG, param)
        if printer isa Function
            print(' ', printer(value))
        else
            print(" $value $printer")
        end
        if value == default
            printstyled(" (default)", color=:light_black)
        else
            dstr = if printer isa Function
                printer(default)
            else default end
            printstyled(" ($dstr by default)", color=:light_black)
        end
        print('\n')
    end
end

function repl_config_set(input::AbstractString)
    if !any(isspace, input)
        printstyled(" ! ", color=:red, bold=true)
        println("must provide a \"{parameter} {value}\" form")
        return
    end
    param, value = split(input, limit=2)
    if param == "auto_gc"
        if (hours = tryparse(Int, hours)) |> !isnothing
            modify_inventory(() -> INVENTORY.config.auto_gc = hours)
        else
            printstyled(" ! ", color=:red, bold=true)
            println("must be an integer")
            return
        end
    elseif param == "max_age"
        if value == "-"
            modify_inventory() do
                INVENTORY.config.max_age = nothing
            end
        elseif (days = tryparse(Int, value)) |> !isnothing
            modify_inventory() do
                INVENTORY.config.max_age = days
            end
        else
            printstyled(" ! ", color=:red, bold=true)
            println("must be a integer")
            return
        end
    elseif param == "max_size"
        if value == "-"
            modify_inventory() do
                INVENTORY.config.max_size = nothing
            end
        else
            try
                bytes = parsebytesize(value)
                modify_inventory() do
                    INVENTORY.config.max_size = bytes
                end
            catch err
                if err isa ArgumentError
                    printstyled(" ! ", color=:red, bold=true)
                    println("must be a byte size (e.g. '5GiB', '100kB')")
                    return
                else
                    rethrow(err)
                end
            end
        end
    elseif param == "recency_beta"
        try
            num = something(tryparse(Int, value), parse(Float64, value))
            modify_inventory(() ->
                INVENTORY.config.recency_beta = num)
        catch err
            if err isa ArgumentError
                printstyled(" ! ", color=:red, bold=true)
                println("must be a (positive) number")
                return
            else
                rethrow(err)
            end
        end
    else
        printstyled(" ! ", color=:red, bold=true)
        println("unrecognised parameter: $param")
        return
    end
    printstyled(" ✓ Done\n", color=:green)
end

function repl_config_reset(input::AbstractString)
    if input == "auto_gc"
        modify_inventory() do
            INVENTORY.config.auto_gc = DEFAULT_INVENTORY_CONFIG.auto_gc
        end
        printstyled(" ✓ ", color=:green)
        println("Set to $(ifelse(DEFAULT_INVENTORY_CONFIG.auto_gc, "on", "off"))")
    elseif input == "max_age"
        modify_inventory() do
            INVENTORY.config.max_age = DEFAULT_INVENTORY_CONFIG.max_age
        end
        printstyled(" ✓ ", color=:green)
        println("Set to $(DEFAULT_INVENTORY_CONFIG.max_age) days")
    elseif input == "max_size"
        modify_inventory() do
            INVENTORY.config.max_size = DEFAULT_INVENTORY_CONFIG.max_size
        end
        printstyled(" ✓ ", color=:green)
        if isnothing(INVENTORY.config.max_size)
            println("Set to unlimited")
        else
            println("Set to $(join(humansize(DEFAULT_INVENTORY_CONFIG.max_size)))")
        end
    elseif input == "recency_beta"
        modify_inventory() do
            INVENTORY.config.recency_beta = DEFAULT_INVENTORY_CONFIG.recency_beta
        end
        printstyled(" ✓ ", color=:green)
        println("Set to $(DEFAULT_INVENTORY_CONFIG.recency_beta)")
    else
        printstyled(" ! ", color=:red, bold=true)
        println("unrecognised parameter: $input")
        return
    end
end

const REPL_CONFIG_KEYS = ["auto_gc", "max_age", "max_size", "recency_beta"]
allcompletions(::ReplCmd{:store_config_get}) = REPL_CONFIG_KEYS
allcompletions(::ReplCmd{:store_config_set}) = REPL_CONFIG_KEYS
allcompletions(::ReplCmd{:store_config_reset}) = REPL_CONFIG_KEYS

function repl_gc(input::AbstractString)
    flags = split(input)
    dryrun = "-d" in flags || "--dryrun" in flags
    update_inventory!()
    garbage_collect!(; dryrun)
end

allcompletions(::ReplCmd{:store_gc}) = ["-d", "--dryrun"]

function repl_expunge(input::AbstractString)
    update_inventory!()
    collection = nothing
    for cltn in INVENTORY.collections
        if cltn.name == input
            collection = cltn
        elseif string(cltn.uuid) == input
            collection = cltn
        end
        isnothing(collection) || break
    end
    if isnothing(collection)
        printstyled(" ! ", color=:red, bold=true)
        println("could not find collection: $input")
        return
    end
    removed = expunge!(collection)
    printstyled(" i ", color=:cyan, bold=true)
    println("removed $(length(removed)) items from the store")
end

allcompletions(::ReplCmd{:store_expunge}) = getfield.(INVENTORY.collections, :name)

const STORE_SUBCMDS =
    ReplCmd[
        ReplCmd{:store_gc}(
            "gc", "Garbage Collect

Scan the inventory and perform a garbage collection sweep.

Optionally provide the -d/--dryrun flag to prevent file deletion.",
            repl_gc),
        ReplCmd{:store_stats}(
            "stats", "Show statistics about the data store",
            _ -> printstats()),
        ReplCmd{:store_config}(
            "config", "Manage configuration",
            ReplCmd[
                ReplCmd{:store_config_get}(
                    "get", "Get the current configuration\n\n$STORE_GC_CONFIG_INFO",
                    repl_config_get),
                ReplCmd{:store_config_set}(
                    "set", "Set a configuration parameter\n\n$STORE_GC_CONFIG_INFO",
                    repl_config_set),
                ReplCmd{:store_config_reset}(
                    "reset", "Set a configuration parameter\n\n$STORE_GC_CONFIG_INFO",
                    repl_config_reset)]),
        ReplCmd{:store_expunge}(
            "expunge", """Remove a data collection from the store
                          \nUsage:\n  expunge [collection name or UUID]""",
            repl_expunge)]

const STORE_REPL_CMD =
    ReplCmd(:store,
            "Manipulate the data store",
            STORE_SUBCMDS)
