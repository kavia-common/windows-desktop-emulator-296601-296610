#!/bin/bash

# Minimal PostgreSQL startup script with full paths
DB_NAME="myapp"
DB_USER="appuser"
DB_PASSWORD="dbuser123"
# Prefer 5001 for preview; allow override via env; fallback to 5000 if needed
DB_PORT="${DB_PORT:-5001}"

echo "Starting PostgreSQL setup..."

# Find PostgreSQL version and set paths
PG_VERSION=$(ls /usr/lib/postgresql/ | head -1)
PG_BIN="/usr/lib/postgresql/${PG_VERSION}/bin"

echo "Found PostgreSQL version: ${PG_VERSION}"

# If 5001 is unavailable but 5000 is available, fallback
if ! sudo -u postgres ${PG_BIN}/pg_isready -p ${DB_PORT} > /dev/null 2>&1; then
  if [ "${DB_PORT}" = "5001" ] && sudo -u postgres ${PG_BIN}/pg_isready -p 5000 > /dev/null 2>&1; then
    echo "Port 5001 not available, falling back to 5000"
    DB_PORT="5000"
  fi
fi

# Check if PostgreSQL is already running on the effective port
if sudo -u postgres ${PG_BIN}/pg_isready -p ${DB_PORT} > /dev/null 2>&1; then
    echo "PostgreSQL is already running on port ${DB_PORT}!"
    echo "Database: ${DB_NAME}"
    echo "User: ${DB_USER}"
    echo "Port: ${DB_PORT}"
    echo ""
    echo "To connect to the database, use:"
    echo "psql -h localhost -U ${DB_USER} -d ${DB_NAME} -p ${DB_PORT}"
    
    # Check if connection info file exists
    if [ -f "db_connection.txt" ]; then
        echo "Or use: $(cat db_connection.txt)"
    fi
    
    echo ""
    echo "Continuing to ensure schema and seed data are present..."
else
  # Also check if there's a PostgreSQL process running (in case pg_isready fails)
  if pgrep -f "postgres.*-p ${DB_PORT}" > /dev/null 2>&1; then
      echo "Found existing PostgreSQL process on port ${DB_PORT}"
      echo "Attempting to verify connection..."
      
      # Try to connect and verify the database exists
      if sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -c '\q' 2>/dev/null; then
          echo "Database ${DB_NAME} is accessible."
      fi
  else
      # Initialize PostgreSQL data directory if it doesn't exist
      if [ ! -f "/var/lib/postgresql/data/PG_VERSION" ]; then
          echo "Initializing PostgreSQL..."
          sudo -u postgres ${PG_BIN}/initdb -D /var/lib/postgresql/data
      fi

      # Start PostgreSQL server in background
      echo "Starting PostgreSQL server..."
      sudo -u postgres ${PG_BIN}/postgres -D /var/lib/postgresql/data -p ${DB_PORT} &

      # Wait for PostgreSQL to start
      echo "Waiting for PostgreSQL to start..."
      sleep 5

      # Check if PostgreSQL is running
      for i in {1..15}; do
          if sudo -u postgres ${PG_BIN}/pg_isready -p ${DB_PORT} > /dev/null 2>&1; then
              echo "PostgreSQL is ready!"
              break
          fi
          echo "Waiting... ($i/15)"
          sleep 2
      done
  fi
fi

# Create database and user
echo "Setting up database and user..."
sudo -u postgres ${PG_BIN}/createdb -p ${DB_PORT} ${DB_NAME} 2>/dev/null || echo "Database might already exist"

# Set up user and permissions with proper schema ownership
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d postgres << EOF
-- Create user if doesn't exist
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}') THEN
        CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}';
    END IF;
    ALTER ROLE ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';
END
\$\$;

-- Grant database-level permissions
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
EOF

# Ensure schema-level permissions inside target DB
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} << EOF
-- For PostgreSQL 15+, handle public schema permissions
GRANT USAGE ON SCHEMA public TO ${DB_USER};
GRANT CREATE ON SCHEMA public TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TYPES TO ${DB_USER};
GRANT ALL ON SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO ${DB_USER};
EOF

# Create schema tables (one statement at a time)
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -c "CREATE TABLE IF NOT EXISTS users (id uuid PRIMARY KEY, username text UNIQUE, created_at timestamptz DEFAULT now());"
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -c "CREATE TABLE IF NOT EXISTS desktop_sessions (id uuid PRIMARY KEY, user_id uuid NULL REFERENCES users(id) ON DELETE SET NULL, created_at timestamptz DEFAULT now(), updated_at timestamptz DEFAULT now());"
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -c "CREATE TABLE IF NOT EXISTS desktop_icons (id uuid PRIMARY KEY, session_id uuid NOT NULL REFERENCES desktop_sessions(id) ON DELETE CASCADE, title text NOT NULL, type text NOT NULL, payload jsonb DEFAULT '{}'::jsonb, x int NOT NULL DEFAULT 0, y int NOT NULL DEFAULT 0, created_at timestamptz DEFAULT now(), updated_at timestamptz DEFAULT now());"
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -c "CREATE TABLE IF NOT EXISTS desktop_windows (id uuid PRIMARY KEY, session_id uuid NOT NULL REFERENCES desktop_sessions(id) ON DELETE CASCADE, title text NOT NULL, app_type text NOT NULL, payload jsonb DEFAULT '{}'::jsonb, x int NOT NULL DEFAULT 100, y int NOT NULL DEFAULT 100, width int NOT NULL DEFAULT 600, height int NOT NULL DEFAULT 400, z_index int NOT NULL DEFAULT 1, state text NOT NULL DEFAULT 'normal', is_focused boolean NOT NULL DEFAULT false, created_at timestamptz DEFAULT now(), updated_at timestamptz DEFAULT now());"
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -c "CREATE TABLE IF NOT EXISTS taskbar_items (id uuid PRIMARY KEY, session_id uuid NOT NULL REFERENCES desktop_sessions(id) ON DELETE CASCADE, window_id uuid NULL REFERENCES desktop_windows(id) ON DELETE SET NULL, pinned boolean NOT NULL DEFAULT false, order_index int NOT NULL DEFAULT 0);"
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -c "CREATE TABLE IF NOT EXISTS settings (id uuid PRIMARY KEY, session_id uuid UNIQUE NOT NULL REFERENCES desktop_sessions(id) ON DELETE CASCADE, theme text DEFAULT 'light', wallpaper_url text);"

# Helpful indexes
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -c "CREATE INDEX IF NOT EXISTS idx_desktop_icons_session ON desktop_icons(session_id);"
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -c "CREATE INDEX IF NOT EXISTS idx_desktop_windows_session ON desktop_windows(session_id);"
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -c "CREATE INDEX IF NOT EXISTS idx_taskbar_items_session ON taskbar_items(session_id);"
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -c "CREATE INDEX IF NOT EXISTS idx_desktop_windows_session_z ON desktop_windows(session_id, z_index);"

# Seed data: default session and icons
DEFAULT_SESSION_ID="00000000-0000-0000-0000-000000000001"
ICON1_ID="00000000-0000-0000-0000-000000000101"
ICON2_ID="00000000-0000-0000-0000-000000000102"

# Insert default session if not exists
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -c "INSERT INTO desktop_sessions (id, user_id) VALUES ('${DEFAULT_SESSION_ID}', NULL) ON CONFLICT (id) DO NOTHING;"
# Insert icons if not exists
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -c "INSERT INTO desktop_icons (id, session_id, title, type, payload, x, y) VALUES ('${ICON1_ID}', '${DEFAULT_SESSION_ID}', 'My Computer', 'system', '{}'::jsonb, 20, 20) ON CONFLICT (id) DO NOTHING;"
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -c "INSERT INTO desktop_icons (id, session_id, title, type, payload, x, y) VALUES ('${ICON2_ID}', '${DEFAULT_SESSION_ID}', 'Recycle Bin', 'system', '{}'::jsonb, 20, 90) ON CONFLICT (id) DO NOTHING;"

# Save connection command to a file
echo "psql postgresql://${DB_USER}:${DB_PASSWORD}@localhost:${DB_PORT}/${DB_NAME}" > db_connection.txt
echo "Connection string saved to db_connection.txt"

# Save environment variables to a file
cat > db_visualizer/postgres.env << EOF
export POSTGRES_URL="postgresql://localhost:${DB_PORT}/${DB_NAME}"
export POSTGRES_USER="${DB_USER}"
export POSTGRES_PASSWORD="${DB_PASSWORD}"
export POSTGRES_DB="${DB_NAME}"
export POSTGRES_PORT="${DB_PORT}"
EOF

echo "PostgreSQL setup complete!"
echo "Database: ${DB_NAME}"
echo "User: ${DB_USER}"
echo "Port: ${DB_PORT}"
echo ""

echo "Environment variables saved to db_visualizer/postgres.env"
echo "To use with Node.js viewer, run: source db_visualizer/postgres.env"

echo "To connect to the database, use one of the following commands:"
echo "psql -h localhost -U ${DB_USER} -d ${DB_NAME} -p ${DB_PORT}"
echo "$(cat db_connection.txt)"
