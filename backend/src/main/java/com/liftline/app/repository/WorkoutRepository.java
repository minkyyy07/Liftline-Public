package com.liftline.app.repository;

import com.liftline.app.entity.Workout;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface WorkoutRepository extends JpaRepository<Workout, UUID> {
    List<Workout> findByUserIdOrderByWorkoutDateDesc(UUID userId);
    /** Stable paging: id is the tie-breaker so equal dates never skip or repeat rows across pages. */
    Page<Workout> findByUserIdOrderByWorkoutDateDescIdAsc(UUID userId, Pageable pageable);
    Optional<Workout> findByIdAndUserId(UUID id, UUID userId);
    boolean existsByIdAndUserId(UUID id, UUID userId);
    void deleteByIdAndUserId(UUID id, UUID userId);
}
