package com.liftline.app.entity;

import jakarta.persistence.*;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "set_entry")
public class SetEntry {
    @Id
    @Column(name = "id", nullable = false, updatable = false, unique = true)
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "exercise_id", nullable = false)
    private WorkoutExercise exercise;

    @Column(name = "set_number", nullable = false)
    private Integer setNumber;

    @Column(name = "weight_kg", precision = 6, scale = 2)
    private BigDecimal weightKg;

    @Column(name = "reps")
    private Integer reps;

    @Column(name = "completed", nullable = false)
    private Boolean completed = true;

    @Column(name = "rpe", precision = 3, scale = 1)
    private BigDecimal rpe;

    @Column(name = "set_type", length = 32)
    private String setType;

    @Column(name = "rest_seconds")
    private Integer restSeconds;

    @Column(name = "notes", length = 500)
    private String notes;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

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
    public WorkoutExercise getExercise() { return exercise; }
    public void setExercise(WorkoutExercise exercise) { this.exercise = exercise; }
    public Integer getSetNumber() { return setNumber; }
    public void setSetNumber(Integer setNumber) { this.setNumber = setNumber; }
    public BigDecimal getWeightKg() { return weightKg; }
    public void setWeightKg(BigDecimal weightKg) { this.weightKg = weightKg; }
    public Integer getReps() { return reps; }
    public void setReps(Integer reps) { this.reps = reps; }
    public Boolean getCompleted() { return completed; }
    public void setCompleted(Boolean completed) { this.completed = completed; }
    public BigDecimal getRpe() { return rpe; }
    public void setRpe(BigDecimal rpe) { this.rpe = rpe; }
    public String getSetType() { return setType; }
    public void setSetType(String setType) { this.setType = setType; }
    public Integer getRestSeconds() { return restSeconds; }
    public void setRestSeconds(Integer restSeconds) { this.restSeconds = restSeconds; }
    public String getNotes() { return notes; }
    public void setNotes(String notes) { this.notes = notes; }
    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(Instant updatedAt) { this.updatedAt = updatedAt; }
}
