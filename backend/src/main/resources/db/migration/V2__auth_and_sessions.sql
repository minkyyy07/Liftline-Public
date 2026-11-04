ALTER TABLE users ADD COLUMN display_name VARCHAR(100);

CREATE TABLE refresh_sessions (
    id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    token_hash VARCHAR(64) NOT NULL,
    family_id BINARY(16) NOT NULL,
    revoked BOOLEAN NOT NULL DEFAULT FALSE,
    replaced_at TIMESTAMP,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP NOT NULL,
    user_agent VARCHAR(255),
    client_ip VARCHAR(64),
    CONSTRAINT pk_refresh_sessions PRIMARY KEY (id),
    CONSTRAINT fk_refresh_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT uq_refresh_token_hash UNIQUE (token_hash)
);

CREATE INDEX idx_refresh_user_family ON refresh_sessions(user_id, family_id);
