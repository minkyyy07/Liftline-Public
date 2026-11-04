package com.liftline.app.dto;

import java.util.UUID;

public class UserProfileDto {
    private UUID id;
    private String email;
    private String displayName;

    public UserProfileDto() {}

    public UserProfileDto(UUID id, String email, String displayName) {
        this.id = id;
        this.email = email;
        this.displayName = displayName;
    }

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }
    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }
    public String getDisplayName() { return displayName; }
    public void setDisplayName(String displayName) { this.displayName = displayName; }
}
