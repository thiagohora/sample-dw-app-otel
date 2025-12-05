package com.example;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

@Path("/latency")
@Produces(MediaType.TEXT_PLAIN)
public class LatencyResource {

    @GET
    public Response simulateLatency(@QueryParam("ms") Integer milliseconds) {
        if (milliseconds == null || milliseconds < 0) {
            return Response.status(Response.Status.BAD_REQUEST)
                    .entity("Please provide a valid 'ms' query parameter (e.g., /latency?ms=1000)")
                    .build();
        }

        try {
            // Simulate latency by sleeping for the specified milliseconds
            Thread.sleep(milliseconds);
            return Response.ok()
                    .entity(String.format("Slept for %d milliseconds", milliseconds))
                    .build();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return Response.status(Response.Status.INTERNAL_SERVER_ERROR)
                    .entity("Sleep was interrupted: " + e.getMessage())
                    .build();
        }
    }
}

