package com.liftline.app.repository;

import com.liftline.app.entity.RefreshSession;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface RefreshSessionRepository extends JpaRepository<RefreshSession, UUID> {
    Optional<RefreshSession> findByTokenHash(String tokenHash);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT r FROM RefreshSession r WHERE r.tokenHash = :tokenHash")
    Optional<RefreshSession> findByTokenHashForUpdate(@Param("tokenHash") String tokenHash);

    List<RefreshSession> findByUserId(UUID userId);

    List<RefreshSession> findByFamilyId(UUID familyId);

    @Modifying(clearAutomatically = true)
    @Query("UPDATE RefreshSession r SET r.revoked = true WHERE r.familyId = :familyId")
    int revokeAllByFamilyId(@Param("familyId") UUID familyId);

    @Modifying(clearAutomatically = true)
    @Query("UPDATE RefreshSession r SET r.revoked = true WHERE r.user.id = :userId")
    int revokeAllByUserId(@Param("userId") UUID userId);

    @Modifying
    @Query("DELETE FROM RefreshSession r WHERE r.expiresAt < :now")
    int deleteExpiredBefore(@Param("now") Instant now);
}
