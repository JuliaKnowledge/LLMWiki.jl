module LLMWikiSQLiteExt

using LLMWiki
using LLMWiki: JSON3
using DBInterface

const SQLite = Base.root_module(
    Base.PkgId(Base.UUID("0aa819cd-b072-5ff4-a722-6bc24af294d9"), "SQLite"),
)

"""
SQLite-backed state storage for LLMWiki.jl.
Provides persistent, queryable state as an alternative to JSON files.
"""

const SCHEMA_SQL = [
    """
    CREATE TABLE IF NOT EXISTS sources (
        file TEXT PRIMARY KEY,
        hash TEXT NOT NULL,
        concepts TEXT NOT NULL DEFAULT '[]',
        compiled_at TEXT NOT NULL DEFAULT '',
        source_url TEXT,
        source_type TEXT NOT NULL DEFAULT 'file',
        original_file TEXT
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS wiki_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS frozen_slugs (
        slug TEXT PRIMARY KEY
    )
    """,
]

const SOURCE_COLUMNS = [
    ("source_url", "TEXT"),
    ("source_type", "TEXT NOT NULL DEFAULT 'file'"),
    ("original_file", "TEXT"),
]

"""
    init_sqlite_state(db_path::String) -> SQLite.DB

Initialize a SQLite database for wiki state storage.
"""
function init_sqlite_state(db_path::String)
    db = SQLite.DB(db_path)
    for stmt in SCHEMA_SQL
        DBInterface.execute(db, stmt)
    end
    _ensure_source_columns!(db)
    return db
end

function _ensure_source_columns!(db::SQLite.DB)
    existing_columns = Set{String}()
    for row in DBInterface.execute(db, "PRAGMA table_info(sources)")
        push!(existing_columns, String(row.name))
    end

    for (name, spec) in SOURCE_COLUMNS
        if name ∉ existing_columns
            DBInterface.execute(db, "ALTER TABLE sources ADD COLUMN $name $spec")
        end
    end

    return nothing
end

_sqlite_path(config::LLMWiki.WikiConfig) = joinpath(config.state_dir, "state.db")

_sqlite_string(value) = value === nothing || value === missing ? nothing : String(value)

"""
    LLMWiki.load_state_sqlite(config::LLMWiki.WikiConfig) -> LLMWiki.WikiState

Load wiki state from SQLite database.
"""
function LLMWiki.load_state_sqlite(config::LLMWiki.WikiConfig)
    LLMWiki.resolve_paths!(config)
    db_path = _sqlite_path(config)
    isfile(db_path) || return LLMWiki.WikiState()

    db = init_sqlite_state(db_path)
    state = LLMWiki.WikiState()

    # Load sources
    results = DBInterface.execute(
        db,
        "SELECT file, hash, concepts, compiled_at, source_url, source_type, original_file FROM sources",
    )
    for row in results
        concepts = try
            JSON3.read(row.concepts, Vector{String})
        catch
            String[]
        end
        state.sources[row.file] = LLMWiki.SourceEntry(
            hash=row.hash,
            concepts=concepts,
            compiled_at=row.compiled_at,
            source_url=_sqlite_string(row.source_url),
            source_type=something(_sqlite_string(row.source_type), "file"),
            original_file=_sqlite_string(row.original_file),
        )
    end

    # Load frozen slugs
    results = DBInterface.execute(db, "SELECT slug FROM frozen_slugs")
    state.frozen_slugs = [row.slug for row in results]

    # Load metadata
    results = DBInterface.execute(
        db,
        "SELECT key, value FROM wiki_meta WHERE key IN ('index_hash', 'state_version')",
    )
    for row in results
        if row.key == "index_hash"
            state.index_hash = row.value
        elseif row.key == "state_version"
            state.version = try
                parse(Int, row.value)
            catch
                state.version
            end
        end
    end

    return state
end

"""
    LLMWiki.save_state_sqlite(config::LLMWiki.WikiConfig, state::LLMWiki.WikiState)

Save wiki state to SQLite database.
"""
function LLMWiki.save_state_sqlite(config::LLMWiki.WikiConfig, state::LLMWiki.WikiState)
    LLMWiki.resolve_paths!(config)
    db_path = _sqlite_path(config)
    mkpath(dirname(db_path))
    db = init_sqlite_state(db_path)

    # Sync sources
    DBInterface.execute(db, "DELETE FROM sources")
    for (file, entry) in state.sources
        concepts_json = JSON3.write(entry.concepts)
        DBInterface.execute(db,
            "INSERT INTO sources (file, hash, concepts, compiled_at, source_url, source_type, original_file) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (
                file,
                entry.hash,
                concepts_json,
                entry.compiled_at,
                entry.source_url,
                entry.source_type,
                entry.original_file,
            ),
        )
    end

    # Sync frozen slugs
    DBInterface.execute(db, "DELETE FROM frozen_slugs")
    for slug in state.frozen_slugs
        DBInterface.execute(db, "INSERT INTO frozen_slugs (slug) VALUES (?)", (slug,))
    end

    # Upsert metadata
    DBInterface.execute(db,
        "INSERT OR REPLACE INTO wiki_meta (key, value) VALUES ('index_hash', ?)",
        (state.index_hash,))
    DBInterface.execute(db,
        "INSERT OR REPLACE INTO wiki_meta (key, value) VALUES ('state_version', ?)",
        (string(state.version),))

    return nothing
end

end # module
