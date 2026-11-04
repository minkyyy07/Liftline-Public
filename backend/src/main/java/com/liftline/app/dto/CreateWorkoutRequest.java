package com.liftline.app.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

public class CreateWorkoutRequest {
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

    @Valid
    private List<WorkoutExerciseDto> exercises = new ArrayList<>();

    public CreateWorkoutRequest() {}

    public LocalDate getWorkoutDate() { return workoutDate; }
    public void setWorkoutDate(LocalDate workoutDate) { this.workoutDate = workoutDate; }
    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }
    public Integer getDurationMinutes() { return durationMinutes; }
    public void setDurationMinutes(Integer durationMinutes) { this.durationMinutes = durationMinutes; }
    public String getNotes() { return notes; }
    public void setNotes(String notes) { this.notes = notes; }
    public List<WorkoutExerciseDto> getExercises() { return exercises; }
    public void setExercises(List<WorkoutExerciseDto> exercises) { this.exercises = exercises; }
}
