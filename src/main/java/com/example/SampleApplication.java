package com.example;

import io.dropwizard.core.Application;
import io.dropwizard.configuration.EnvironmentVariableSubstitutor;
import io.dropwizard.configuration.SubstitutingSourceProvider;
import io.dropwizard.core.setup.Bootstrap;
import io.dropwizard.core.setup.Environment;
import ru.vyarus.dropwizard.guice.GuiceBundle;

public class SampleApplication extends Application<SampleConfiguration> {

    public static void main(String[] args) throws Exception {
        new SampleApplication().run(args);
    }

    @Override
    public void initialize(Bootstrap<SampleConfiguration> bootstrap) {
        var substitutor = new EnvironmentVariableSubstitutor(false);
        var provider = new SubstitutingSourceProvider(bootstrap.getConfigurationSourceProvider(), substitutor);
        bootstrap.setConfigurationSourceProvider(provider);
        bootstrap.addBundle(GuiceBundle.builder()
                .enableAutoConfig()
                .build());
    }

    @Override
    public void run(SampleConfiguration configuration, Environment environment) {
        // Resources are automatically registered by Guicey
    }
}

