package com.liftline.app.controller;

import com.liftline.app.dto.CreateWorkoutRequest;
import com.liftline.app.dto.UpdateWorkoutRequest;
import com.liftline.app.dto.WorkoutDto;
import com.liftline.app.entity.Workout;
import com.liftline.app.service.WorkoutService;
import jakarta.validation.Valid;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/workouts")
public class WorkoutController {

    private final WorkoutService workoutService;

    public WorkoutController(WorkoutService workoutService) {
        this.workoutService = workoutService;
    }

    @GetMapping
    public ResponseEntity<?> getWorkouts(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        // Enforce maximum page size to prevent denial-of-service through unbounded queries
        int clampedSize = Math.max(1, Math.min(size, 100));
        int validPage = Math.max(0, page);
        Pageable pageable = PageRequest.of(validPage, clampedSize);

        List<WorkoutDto> dtoList = workoutService.getCurrentUserWorkoutsDto(pageable);
        return ResponseEntity.ok(dtoList);
    }

    @GetMapping("/{id}")
    public ResponseEntity<WorkoutDto> getWorkoutById(@PathVariable UUID id) {
        WorkoutDto workoutDto = workoutService.getWorkoutDtoByIdForCurrentUser(id);
        return ResponseEntity.ok(workoutDto);
    }

    @PostMapping
    public ResponseEntity<WorkoutDto> createWorkout(@Valid @RequestBody CreateWorkoutRequest request) {
        Workout created = workoutService.createWorkoutFromRequest(request);
        return ResponseEntity.status(HttpStatus.CREATED).body(workoutService.toDto(created));
    }

    @PutMapping("/{id}")
    public ResponseEntity<WorkoutDto> updateWorkout(
            @PathVariable UUID id,
            @Valid @RequestBody UpdateWorkoutRequest request) {
        Workout updated = workoutService.updateWorkoutFromRequest(id, request);
        return ResponseEntity.ok(workoutService.toDto(updated));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> deleteWorkout(@PathVariable UUID id) {
        workoutService.deleteWorkoutForCurrentUser(id);
        return ResponseEntity.noContent().build();
    }
}
