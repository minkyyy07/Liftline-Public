package com.liftline.app.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

public class UpdateWorkoutRequest extends PartialDto {
    private Instant clientUpdatedAt;
    private Long version;

    @NotNull(message = "Workout date is required")
    private LocalDate workoutDate;

    @NotBlank(message = "Title must not be blank")
    @Size(max = 255, message = "Title must not exceed 255 characters")
    private String title;

    @Min(value = 0, message = "Duration cannot be negative")
    @Max(value = 1440, message = "Duration cannot exceed 1440 minutes")
    private Integer durationMinutes;

    @Size(max = 1000, message = "Notes cannot exceed 1000 characters")
    private String notes;

    @Pattern(regexp = "planned|active|finished", message = "Status must be planned, active or finished")
    private String status;

    private Instant startedAtUtc;
    private Instant finishedAtUtc;

    @Valid
    private List<WorkoutExerciseDto> exercises = new ArrayList<>();

    public UpdateWorkoutRequest() {}

    public Instant getClientUpdatedAt() { return clientUpdatedAt; }
    public void setClientUpdatedAt(Instant clientUpdatedAt) { this.clientUpdatedAt = clientUpdatedAt; }

    public Long getVersion() { return version; }
    public void setVersion(Long version) { this.version = version; }

    public LocalDate getWorkoutDate() { return workoutDate; }
    public void setWorkoutDate(LocalDate workoutDate) { this.workoutDate = workoutDate; }
    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }
    public Integer getDurationMinutes() { return durationMinutes; }
    public void setDurationMinutes(Integer durationMinutes) { this.durationMinutes = durationMinutes; markPresent("durationMinutes"); }
    public String getNotes() { return notes; }
    public void setNotes(String notes) { this.notes = notes; markPresent("notes"); }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; markPresent("status"); }
    public Instant getStartedAtUtc() { return startedAtUtc; }
    public void setStartedAtUtc(Instant startedAtUtc) { this.startedAtUtc = startedAtUtc; markPresent("startedAtUtc"); }
    public Instant getFinishedAtUtc() { return finishedAtUtc; }
    public void setFinishedAtUtc(Instant finishedAtUtc) { this.finishedAtUtc = finishedAtUtc; markPresent("finishedAtUtc"); }
    public List<WorkoutExerciseDto> getExercises() { return exercises; }
    public void setExercises(List<WorkoutExerciseDto> exercises) { this.exercises = exercises; markPresent("exercises"); }
}
