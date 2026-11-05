package com.liftline.app.dto;

import com.fasterxml.jackson.annotation.JsonIgnore;

import java.util.HashSet;
import java.util.Set;

/**
 * Base for request DTOs that must tell a MISSING JSON field (keep the stored value)
 * apart from an explicit null (clear it). Jackson only calls a setter when the key is
 * present in the payload, so each setter records its field name here.
 * Java callers that never touch a setter therefore get "keep existing" semantics.
 */
public abstract class PartialDto {

    @JsonIgnore
    private final Set<String> presentFields = new HashSet<>();

    @JsonIgnore
    protected final void markPresent(String field) {
        presentFields.add(field);
    }

    @JsonIgnore
    public final boolean isPresent(String field) {
        return presentFields.contains(field);
    }
}
