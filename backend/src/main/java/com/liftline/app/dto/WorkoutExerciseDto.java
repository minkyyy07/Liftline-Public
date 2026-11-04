package com.liftline.app.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

public class WorkoutExerciseDto {
    private UUID id;

    @NotBlank(message = "Exercise name must not be blank")
    @Size(max = 255, message = "Exercise name must not exceed 255 characters")
    private String exerciseName;

    @NotNull(message = "Sort order is required")
    private Integer sortOrder;

    @Valid
    private List<SetEntryDto> sets = new ArrayList<>();

    public WorkoutExerciseDto() {}

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }
    public String getExerciseName() { return exerciseName; }
    public void setExerciseName(String exerciseName) { this.exerciseName = exerciseName; }
    public Integer getSortOrder() { return sortOrder; }
    public void setSortOrder(Integer sortOrder) { this.sortOrder = sortOrder; }
    public List<SetEntryDto> getSets() { return sets; }
    public void setSets(List<SetEntryDto> sets) { this.sets = sets; }
}
