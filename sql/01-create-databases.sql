-- Nine databases, one MySQL instance. Applied by scripts/pc/01-Create-Databases.ps1.
-- Safe to re-run: every statement is IF NOT EXISTS.

-- Vanilla (CMaNGOS-classic)
CREATE DATABASE IF NOT EXISTS classicmangos     DEFAULT CHARSET utf8mb4;
CREATE DATABASE IF NOT EXISTS classiccharacters DEFAULT CHARSET utf8mb4;
CREATE DATABASE IF NOT EXISTS classicrealmd     DEFAULT CHARSET utf8mb4;

-- TBC (CMaNGOS-tbc)
CREATE DATABASE IF NOT EXISTS tbcmangos     DEFAULT CHARSET utf8mb4;
CREATE DATABASE IF NOT EXISTS tbccharacters DEFAULT CHARSET utf8mb4;
CREATE DATABASE IF NOT EXISTS tbcrealmd     DEFAULT CHARSET utf8mb4;

-- WotLK (AzerothCore, Playerbot fork)
CREATE DATABASE IF NOT EXISTS acore_world      DEFAULT CHARSET utf8mb4;
CREATE DATABASE IF NOT EXISTS acore_characters DEFAULT CHARSET utf8mb4;
CREATE DATABASE IF NOT EXISTS acore_auth       DEFAULT CHARSET utf8mb4;
