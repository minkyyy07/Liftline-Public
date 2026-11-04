package com.liftline.app.dto;

import jakarta.validation.constraints.Size;

public class UpdateProfileRequest {
    @Size(max = 100, message = "Display name must not exceed 100 characters")
    private String displayName;

    public UpdateProfileRequest() {}

    public UpdateProfileRequest(String displayName) {
        this.displayName = displayName;
    }

    public String getDisplayName() { return displayName; }
    public void setDisplayName(String displayName) { this.displayName = displayName; }
}
