package com.liftline.app.dto;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

public class SetEntryDto extends PartialDto {
    private UUID id;

    @NotNull(message = "Set number is required")
    @Min(value = 1, message = "Set number must be at least 1")
    private Integer setNumber;

    @DecimalMin(value = "0.0", message = "Weight cannot be negative")
    @DecimalMax(value = "2000.0", message = "Weight cannot exceed 2000 kg")
    private BigDecimal weightKg;

    @Min(value = 0, message = "Reps cannot be negative")
    private Integer reps;

    private Boolean completed = true;

    private BigDecimal rpe;

    @Size(max = 32, message = "Set type cannot exceed 32 characters")
    private String setType;

    @Min(value = 0, message = "Rest seconds cannot be negative")
    private Integer restSeconds;

    @Size(max = 500, message = "Notes cannot exceed 500 characters")
    private String notes;

    @Min(value = 0, message = "RIR cannot be negative")
    private Integer rir;

    private Instant completedAtUtc;

    public SetEntryDto() {}

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }
    public Integer getSetNumber() { return setNumber; }
    public void setSetNumber(Integer setNumber) { this.setNumber = setNumber; }
    public BigDecimal getWeightKg() { return weightKg; }
    public void setWeightKg(BigDecimal weightKg) { this.weightKg = weightKg; markPresent("weightKg"); }
    public Integer getReps() { return reps; }
    public void setReps(Integer reps) { this.reps = reps; markPresent("reps"); }
    public Boolean getCompleted() { return completed; }
    public void setCompleted(Boolean completed) { this.completed = completed; markPresent("completed"); }
    public BigDecimal getRpe() { return rpe; }
    public void setRpe(BigDecimal rpe) { this.rpe = rpe; markPresent("rpe"); }
    public String getSetType() { return setType; }
    public void setSetType(String setType) { this.setType = setType; markPresent("setType"); }
    public Integer getRestSeconds() { return restSeconds; }
    public void setRestSeconds(Integer restSeconds) { this.restSeconds = restSeconds; markPresent("restSeconds"); }
    public String getNotes() { return notes; }
    public void setNotes(String notes) { this.notes = notes; markPresent("notes"); }
    public Integer getRir() { return rir; }
    public void setRir(Integer rir) { this.rir = rir; markPresent("rir"); }
    public Instant getCompletedAtUtc() { return completedAtUtc; }
    public void setCompletedAtUtc(Instant completedAtUtc) { this.completedAtUtc = completedAtUtc; markPresent("completedAtUtc"); }
}
