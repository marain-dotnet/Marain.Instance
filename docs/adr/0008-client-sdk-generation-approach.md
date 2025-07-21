# Updated approach for generating API client SDKs

## Status

2025-07-18 - Proposed

Please write an Architectural Decision Record document comparing current options for generating a C# client library for an API from its OpenAPI definition. At a minimum, include the following tools: Autorest, Kiota, NSwag and OpenAPI Generator. Also include any similar and comparable tools. Do not include untested marketing claims. Think deeply.

## Context

Historically, client SDKs for Marain services were generated using the Autorest tool with some additional files added to handle authenticated vs. anonymous API access and DI container registration.

`Marain.Tenancy`, `Marain.Operations`, `Marain.Claims` and `Marain.Workflow` all use this approach. The only exception is `Marain.UserNotifications`; this uses a hand coded API client build to allow clients to take advantage of hypermedia links provided in the returned HAL documents.

At the time the clients were last generated, Autorest generated code with dependencies on the `Microsoft.Rest` and `Newtonsoft.Json` packages. `Microsoft.Rest` is now deprecated in favour of `Azure.Core`, and has known security vulnerabilities. Json.NET is no longer actively maintained and Microsoft's recommended approach is to migrated to `System.Text.Json`.

Autorest has changed significantly since we initially chose it for API client generation, so it is necessary to review that decision as part of our work to update the Marain libraries to .NET 8.0 and remove dependencies on `Newtonsoft.Json`

## Requirements

- Support for OpenAPI 3.0+ specifications
- Generation of strongly-typed C# clients
- Async/await pattern support
- Dependency injection compatibility
- Customizable HTTP client configuration
- Comprehensive error handling
- Active maintenance and community support
- Integration with CI/CD pipelines
- Support for authentication schemes (Bearer, API Key, OAuth2)
- No dependencies on libraries with documented vulnerabilities
- Uses System.Text.Json rather than Newtonsoft.Json

## Decision Drivers

- Code Quality: Generated code should be clean, readable, and follow C# conventions
- Feature Completeness: Support for modern OpenAPI features and C# language constructs
- Maintainability: Active development, regular updates, and community support
- Integration: Compatibility with existing .NET toolchain and frameworks
- Performance: Efficient HTTP client usage and minimal overhead
- Customization: Ability to modify generation templates and behavior
- Documentation: Quality of generated XML documentation and examples

## Options

### Client generation tools

There are a number of candidate tools we have reviewed as part of this ADR.

#### Autorest

https://github.com/Azure/autorest

Autorest is Microsoft's enterprise-grade client generator for Azure services. Since it was previously used to generate Marain client libraries, the dependency on `Microsoft.Rest` has been replaced with one on `Azure.Core.Pipelines`. The dependency on `Newtonsoft.Json` has also been removed.

**Strengths**
- Battle-tested with extensive production usage
- Comprehensive OpenAPI specification support
- Well-documented with extensive examples
- Strong Azure SDK integration (used by Microsoft internally)
- Supports multiple .NET Framework versions


**Weaknesses**
- In maintenance mode - no new feature development
- Outdated code generation patterns (pre-modern C# features)
- Limited support for nullable reference types
- Generated code can be verbose and dated
- Complex configuration and customization process

#### Kiota

https://learn.microsoft.com/en-us/openapi/kiota/overview

Kiota is Microsoft's more modern client generator.

**Strengths**
- First-party Microsoft tool with strong future support guarantee
- Built specifically for modern .NET (6+) and C# language features
- Excellent support for Microsoft Graph and Azure services
- Strong typing with nullable reference types support
- Built-in support for dependency injection patterns
- Implements Microsoft's API client patterns and conventions
- Active development with regular feature additions
- Good integration with Visual Studio and MSBuild

**Weaknesses**
- Relatively new tool with smaller community compared to alternatives
- Limited template customization options compared to mature tools
- Primarily optimized for Microsoft's API patterns, may not suit all API designs
- Less extensive third-party plugin ecosystem
- Some advanced OpenAPI features still in development

#### NSwag

https://github.com/RicoSuter/NSwag

**Strengths**
- Good Visual Studio integration with GUI configuration
- Support for both client and server-side code generation
- Highly customizable with extensive configuration options
- Good support for inheritance and polymorphism
- Active community development and regular updates
- Supports both OpenAPI 2.0 and 3.0+
- Built-in support for various authentication methods

**Weaknesses**
- Steeper learning curve due to extensive configuration options
- Generated code can be complex for simple APIs
- Template customization requires C# knowledge
- Documentation can be overwhelming for simple use cases
- Some configuration options conflict or produce unexpected results

#### OpenApi Generator

https://openapi-generator.tech/docs/installation

OpenAPI Generator is a community-driven multi-language client generator.

**Strengths**
- Largest community and most active development
- Extensive customization through Mustache templates
- Support for numerous C# client libraries (RestSharp, HttpClient, etc.)
- Regular updates and broad OpenAPI specification support
- Cross-platform compatibility
- Extensive configuration options
- Strong documentation and community resources

**Weaknesses**
- Generic approach may not leverage C#-specific features optimally
- Template system can be complex to modify
- Quality varies across different generators
- Generated code style may not match project conventions
- Configuration complexity for advanced scenarios
- Less integration with Microsoft tooling; requires Java Runtime Environment
- Inconsistent code quality across different language generators

### Hand coded client library

This approach was used to build the client SDK for Marian.UserNotifications. This was primarily an experiment to see if the outcome was worth the effort. It did have a significant advantage at the time, in that it allowed the client to make use of links returned in HAL documents to request further resources. However, this functionality is also provided by Kiota.

### Combination approach

As part of the Autorest documentation, Microsoft state that the Azure SDK libraries are built by generating the core of each client using Autorest, then adding hand-coded "convenience layer" on top (see https://devblogs.microsoft.com/azure-sdk/code-generation-with-autorest/).

This approach would allow us to take the benefits of code generation for the majority of the code, whilst allowing us to provide a simple and consistent interface and client for consumers of Marain APIs.

**Advantages**
- Majority of the code generated automatically
- Interfaces can remain consistent even if the underlying code generation tool is changed in future

**Disadvantages**
- Requires more work than simply using the generated code directly.

## Decision

Use Kiota to generate the core of the client libraries and build a convenience layer over the top to simplify use and allow clients to easily mock the dependency. Keep the new interfaces as similar as possible to existing interfaces where possible, adding new methods to take advantage of using links to request child resources where appropriate.

## Consequences

### Positive

- Dependency is on Microsoft's current tool of choice, so it should be supported for the forseable future.
- Convenience layer will insulate clients from future changes to the underlying generation tool
- Convenience layer will hide any oddities in generated code that might result from Kiota's opinionated approach to generation

### Negative

- More effort than just using generated code
- Consumers will end up with a transitive dependency on Kiota