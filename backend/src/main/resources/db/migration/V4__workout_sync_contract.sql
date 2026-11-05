-- Workout sync contract: lifecycle state, plan fields, RIR, catalogue reference.
-- Additive only. Existing rows keep their data; pre-existing workouts are historical,
-- so they default to 'finished' (same policy as the Flutter v1->v2 migration).
ALTER TABLE workout ADD COLUMN status VARCHAR(16) NOT NULL DEFAULT 'finished';
ALTER TABLE workout ADD COLUMN started_at TIMESTAMP(3) NULL;
ALTER TABLE workout ADD COLUMN finished_at TIMESTAMP(3) NULL;

ALTER TABLE workout_exercise ADD COLUMN exercise_ref_id VARCHAR(64) NULL;
ALTER TABLE workout_exercise ADD COLUMN notes VARCHAR(500) NULL;
ALTER TABLE workout_exercise ADD COLUMN plan_sets INT NULL;
ALTER TABLE workout_exercise ADD COLUMN plan_rep_min INT NULL;
ALTER TABLE workout_exercise ADD COLUMN plan_rep_max INT NULL;
ALTER TABLE workout_exercise ADD COLUMN plan_rir INT NULL;
ALTER TABLE workout_exercise ADD COLUMN plan_rest_sec INT NULL;

ALTER TABLE set_entry ADD COLUMN rir INT NULL;
ALTER TABLE set_entry ADD COLUMN completed_at TIMESTAMP(3) NULL;

CREATE INDEX idx_workout_user_date_id ON workout (user_id, workout_date, id);
