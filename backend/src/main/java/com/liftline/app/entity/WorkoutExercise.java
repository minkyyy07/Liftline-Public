package com.liftline.app.entity;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@Entity
@Table(name = "workout_exercise")
public class WorkoutExercise {
    @Id
    @Column(name = "id", nullable = false, updatable = false, unique = true)
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "workout_id", nullable = false)
    private Workout workout;

    @Column(name = "exercise_name", nullable = false, length = 255)
    private String exerciseName;

    @Column(name = "sort_order", nullable = false)
    private Integer sortOrder;

    /** Local catalogue id (exercises.id on the client). Opaque to the server. */
    @Column(name = "exercise_ref_id", length = 64)
    private String exerciseRefId;

    @Column(name = "notes", length = 500)
    private String notes;

    @Column(name = "plan_sets")
    private Integer planSets;

    @Column(name = "plan_rep_min")
    private Integer planRepMin;

    @Column(name = "plan_rep_max")
    private Integer planRepMax;

    @Column(name = "plan_rir")
    private Integer planRir;

    @Column(name = "plan_rest_sec")
    private Integer planRestSec;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @OneToMany(mappedBy = "exercise", cascade = CascadeType.ALL, orphanRemoval = true)
    @OrderBy("setNumber ASC")
    private List<SetEntry> sets = new ArrayList<>();

    @PrePersist
    public void prePersist() {
        if (id == null) {
            id = UUID.randomUUID();
        }
        Instant now = Instant.now();
        if (createdAt == null) createdAt = now;
        if (updatedAt == null) updatedAt = now;
    }

    @PreUpdate
    public void preUpdate() {
        if (createdAt == null) createdAt = Instant.now();
        updatedAt = Instant.now();
    }

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }
    public Workout getWorkout() { return workout; }
    public void setWorkout(Workout workout) { this.workout = workout; }
    public String getExerciseName() { return exerciseName; }
    public void setExerciseName(String exerciseName) { this.exerciseName = exerciseName; }
    public Integer getSortOrder() { return sortOrder; }
    public void setSortOrder(Integer sortOrder) { this.sortOrder = sortOrder; }
    public String getExerciseRefId() { return exerciseRefId; }
    public void setExerciseRefId(String exerciseRefId) { this.exerciseRefId = exerciseRefId; }
    public String getNotes() { return notes; }
    public void setNotes(String notes) { this.notes = notes; }
    public Integer getPlanSets() { return planSets; }
    public void setPlanSets(Integer planSets) { this.planSets = planSets; }
    public Integer getPlanRepMin() { return planRepMin; }
    public void setPlanRepMin(Integer planRepMin) { this.planRepMin = planRepMin; }
    public Integer getPlanRepMax() { return planRepMax; }
    public void setPlanRepMax(Integer planRepMax) { this.planRepMax = planRepMax; }
    public Integer getPlanRir() { return planRir; }
    public void setPlanRir(Integer planRir) { this.planRir = planRir; }
    public Integer getPlanRestSec() { return planRestSec; }
    public void setPlanRestSec(Integer planRestSec) { this.planRestSec = planRestSec; }
    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(Instant updatedAt) { this.updatedAt = updatedAt; }
    public List<SetEntry> getSets() { return sets; }
    public void setSets(List<SetEntry> sets) { this.sets = sets; }
}
