module LLMWikiSQLiteExt

using LLMWiki
using LLMWiki: JSON3
using SQLite
using DBInterface

"""
SQLite-backed state storage for LLMWiki.jl.
Provides persistent, queryable state as an alternative to JSON files.
"""

const SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS sources (
    file TEXT PRIMARY KEY,
    hash TEXT NOT NULL,
    concepts TEXT NOT NULL DEFAULT '[]',
    compiled_at TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS wiki_meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS frozen_slugs (
    slug TEXT PRIMARY KEY
);
"""

"""
    init_sqlite_state(db_path::String) -> SQLite.DB

Initialize a SQLite database for wiki state storage.
"""
function init_sqlite_state(db_path::String)
    db = SQLite.DB(db_path)
    DBInterface.execute(db, SCHEMA_SQL)
    return db
end

"""
    LLMWiki.load_state_sqlite(config::LLMWiki.WikiConfig) -> LLMWiki.WikiState

Load wiki state from SQLite database.
"""
function LLMWiki.load_state_sqlite(config::LLMWiki.WikiConfig)
    db_path = joinpath(config.root, config.state_dir, "state.db")
    isfile(db_path) || return LLMWiki.WikiState()

    db = SQLite.DB(db_path)
    state = LLMWiki.WikiState()

    # Load sources
    results = DBInterface.execute(db, "SELECT file, hash, concepts, compiled_at FROM sources")
    for row in results
        concepts = try
            JSON3.read(row.concepts, Vector{String})
        catch
            String[]
        end
        state.sources[row.file] = LLMWiki.SourceEntry(
            hash=row.hash,
            concepts=concepts,
            compiled_at=row.compiled_at
        )
    end

    # Load frozen slugs
    results = DBInterface.execute(db, "SELECT slug FROM frozen_slugs")
    state.frozen_slugs = [row.slug for row in results]

    # Load metadata
    results = DBInterface.execute(db, "SELECT key, value FROM wiki_meta WHERE key = 'index_hash'")
    for row in results
        state.index_hash = row.value
    end

    return state
end

"""
    LLMWiki.save_state_sqlite(config::LLMWiki.WikiConfig, state::LLMWiki.WikiState)

Save wiki state to SQLite database.
"""
function LLMWiki.save_state_sqlite(config::LLMWiki.WikiConfig, state::LLMWiki.WikiState)
    db_path = joinpath(config.root, config.state_dir, "state.db")
    mkpath(dirname(db_path))
    db = init_sqlite_state(db_path)

    # Upsert sources
    for (file, entry) in state.sources
        concepts_json = JSON3.write(entry.concepts)
        DBInterface.execute(db,
            "INSERT OR REPLACE INTO sources (file, hash, concepts, compiled_at) VALUES (?, ?, ?, ?)",
            (file, entry.hash, concepts_json, entry.compiled_at))
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

    return nothing
end

end # module
