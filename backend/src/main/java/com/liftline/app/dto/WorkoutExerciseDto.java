package com.liftline.app.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

public class WorkoutExerciseDto extends PartialDto {
    private UUID id;

    @NotBlank(message = "Exercise name must not be blank")
    @Size(max = 255, message = "Exercise name must not exceed 255 characters")
    private String exerciseName;

    @NotNull(message = "Sort order is required")
    private Integer sortOrder;

    @Size(max = 64, message = "Exercise reference cannot exceed 64 characters")
    private String exerciseRefId;

    @Size(max = 500, message = "Exercise notes cannot exceed 500 characters")
    private String notes;

    private Integer planSets;
    private Integer planRepMin;
    private Integer planRepMax;
    private Integer planRir;
    private Integer planRestSec;

    @Valid
    private List<SetEntryDto> sets = new ArrayList<>();

    public WorkoutExerciseDto() {}

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }
    public String getExerciseName() { return exerciseName; }
    public void setExerciseName(String exerciseName) { this.exerciseName = exerciseName; }
    public Integer getSortOrder() { return sortOrder; }
    public void setSortOrder(Integer sortOrder) { this.sortOrder = sortOrder; }
    public String getExerciseRefId() { return exerciseRefId; }
    public void setExerciseRefId(String exerciseRefId) { this.exerciseRefId = exerciseRefId; markPresent("exerciseRefId"); }
    public String getNotes() { return notes; }
    public void setNotes(String notes) { this.notes = notes; markPresent("notes"); }
    public Integer getPlanSets() { return planSets; }
    public void setPlanSets(Integer planSets) { this.planSets = planSets; markPresent("planSets"); }
    public Integer getPlanRepMin() { return planRepMin; }
    public void setPlanRepMin(Integer planRepMin) { this.planRepMin = planRepMin; markPresent("planRepMin"); }
    public Integer getPlanRepMax() { return planRepMax; }
    public void setPlanRepMax(Integer planRepMax) { this.planRepMax = planRepMax; markPresent("planRepMax"); }
    public Integer getPlanRir() { return planRir; }
    public void setPlanRir(Integer planRir) { this.planRir = planRir; markPresent("planRir"); }
    public Integer getPlanRestSec() { return planRestSec; }
    public void setPlanRestSec(Integer planRestSec) { this.planRestSec = planRestSec; markPresent("planRestSec"); }
    public List<SetEntryDto> getSets() { return sets; }
    public void setSets(List<SetEntryDto> sets) { this.sets = sets; markPresent("sets"); }
}
