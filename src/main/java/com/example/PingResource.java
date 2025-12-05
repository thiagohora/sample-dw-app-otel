package com.example;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

@Path("/ping")
@Produces(MediaType.TEXT_PLAIN)
public class PingResource {

    @GET
    public String ping() {
        return "pong";
    }
}

