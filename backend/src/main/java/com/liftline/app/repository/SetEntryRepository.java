package com.liftline.app.repository;

import com.liftline.app.entity.SetEntry;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

public interface SetEntryRepository extends JpaRepository<SetEntry, UUID> {
}
