CREATE TABLE users (
    id BINARY(16) NOT NULL,
    email VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP NOT NULL,
    CONSTRAINT pk_users PRIMARY KEY (id),
    CONSTRAINT uq_users_email UNIQUE (email)
);

CREATE TABLE workout (
    id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    workout_date DATE NOT NULL,
    title VARCHAR(255) NOT NULL,
    duration_minutes INT,
    notes VARCHAR(1000),
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    CONSTRAINT pk_workout PRIMARY KEY (id),
    CONSTRAINT fk_workout_user FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE workout_exercise (
    id BINARY(16) NOT NULL,
    workout_id BINARY(16) NOT NULL,
    exercise_name VARCHAR(255) NOT NULL,
    sort_order INT NOT NULL,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    CONSTRAINT pk_workout_exercise PRIMARY KEY (id),
    CONSTRAINT fk_exercise_workout FOREIGN KEY (workout_id) REFERENCES workout(id)
);

CREATE TABLE set_entry (
    id BINARY(16) NOT NULL,
    exercise_id BINARY(16) NOT NULL,
    set_number INT NOT NULL,
    weight_kg DECIMAL(6,2),
    reps INT,
    completed BOOLEAN NOT NULL DEFAULT TRUE,
    rpe DECIMAL(3,1),
    set_type VARCHAR(32),
    rest_seconds INT,
    notes VARCHAR(500),
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    CONSTRAINT pk_set_entry PRIMARY KEY (id),
    CONSTRAINT fk_set_entry_exercise FOREIGN KEY (exercise_id) REFERENCES workout_exercise(id)
);

CREATE TABLE nutrition_entry (
    id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    entry_date DATE NOT NULL,
    name VARCHAR(255) NOT NULL,
    portion VARCHAR(255),
    calories INT NOT NULL,
    protein_g DECIMAL(6,2),
    fat_g DECIMAL(6,2),
    carbs_g DECIMAL(6,2),
    meal_type VARCHAR(32),
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    CONSTRAINT pk_nutrition_entry PRIMARY KEY (id),
    CONSTRAINT fk_nutrition_user FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE TABLE nutrition_goal (
    id BINARY(16) NOT NULL,
    user_id BINARY(16) NOT NULL,
    date DATE NOT NULL,
    calories INT,
    protein_g DECIMAL(6,2),
    fat_g DECIMAL(6,2),
    carbs_g DECIMAL(6,2),
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    CONSTRAINT pk_nutrition_goal PRIMARY KEY (id),
    CONSTRAINT fk_goal_user FOREIGN KEY (user_id) REFERENCES users(id)
);
