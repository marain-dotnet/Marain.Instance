# Updated approach for generating API client SDKs

## Status

2025-07-18 - Proposed

## Context

Historically, client SDKs for Marain services were generated using the Autorest tool with some additional files added to handle authenticated vs. anonymous API access and DI container registration.

`Marain.Tenancy`, `Marain.Operations`, `Marain.Claims` and `Marain.Workflow` all use this approach. The only exception is `Marain.UserNotifications`; this uses a hand coded API client build to allow clients to take advantage of hypermedia links provided in the returned HAL documents.

At the time the clients were last generated, Autorest generated code with dependencies on the `Microsoft.Rest` and `Newtonsoft.Json` packages. `Microsoft.Rest` is now deprecated in favour of `Azure.Core`, and has known security vulnerabilities. Json.NET is no longer actively maintained and Microsoft's recommended approach is to migrated to `System.Text.Json`.

Autorest has changed significantly since we initially chose it for API client generation, so it is necessary to review that decision as part of our work to move the Marain libraries to .NET 8.0 and remove dependencies on `Newtonsoft.Json`

## Options

### Client generation tools

There are a number of candidate tools we have reviewed as part of this ADR.

#### Autorest

https://github.com/Azure/autorest

Autorest is Microsoft's enterprise-grade client generator for Azure services. Since it was previously used to generate Marain client libraries, the dependency on `Microsoft.Rest` has been replaced with one on `Azure.Core.Pipelines`. The dependency on `Newtonsoft.Json` has also been removed.

**Strengths**
- Enterprise-proven: Extensively used by Microsoft Azure services and battle-tested at scale
- Mature ecosystem: Well-established with comprehensive documentation and community support
- Flexible architecture: Extensible plugin system allows customization for specific needs
- Multiple language support: Supports C#, PowerShell, Go, Java, Node.js, TypeScript, Python
- Configuration options: Extensive configuration capabilities for fine-tuning generated code

**Weaknesses**

- Complexity: Higher learning curve and more complex configuration
- Older architecture: Based on older code generation patterns, may feel dated
- Setup overhead: Requires more initial setup and configuration
- Documentation scattered: Some documentation is Azure-specific

**Recommended For**
- Large-scale enterprise applications
- APIs that require extensive customization
- Teams already using Azure services
- Multi-language client generation requirements

#### Kiota

https://learn.microsoft.com/en-us/openapi/kiota/overview

Kiota is Microsoft's more modern client generator.

**Strengths**
- Modern approach: Next-generation client generation with contemporary patterns
- Lightweight clients: Generates smaller, more efficient client libraries
- Excellent .NET integration: Native support for modern .NET patterns and practices
- Clear documentation: Well-documented with excellent Microsoft Learn content
- Strongly typed: Provides excellent IntelliSense and compile-time safety
- Active development: Actively maintained and improved by Microsoft

**Weaknesses**
- Newer tool: Less mature than AutoRest, smaller community
- OpenAPI 3.0 focus: Works best with OpenAPI 3.0+ specifications
- Limited customization: Less flexible than AutoRest for complex scenarios
- Approach to client generation will make it harder for consumers to mock out the dependency when unit testing

**Best For**
- Modern .NET applications
- Teams preferring contemporary development patterns
- APIs with clean OpenAPI 3.0 specifications
- Projects requiring lightweight, efficient clients

#### NSwag

https://github.com/RicoSuter/NSwag

**Strengths**
- Tight .NET integration: Seamless integration with ASP.NET Core and .NET ecosystem
- Dual functionality: Can generate both OpenAPI specs and client code
- Visual tooling: NSwag Studio provides GUI for configuration
- MSBuild integration: Excellent integration with .NET build process
- TypeScript support: Strong TypeScript client generation
- Real-time generation: Can generate clients during build process

**Weaknesses**
- Primarily .NET focused: Limited support for other languages
- Community maintained: Smaller team compared to Microsoft-backed tools
- Documentation gaps: Some advanced scenarios lack comprehensive documentation

**Best For**
- .NET-centric environments
- Teams using ASP.NET Core
- Projects requiring TypeScript clients
- Scenarios where you control both API and client

#### OpenApi Generator

https://openapi-generator.tech/docs/installation

OpenAPI Generator is a community-driven multi-language client generator.

**Strengths**
- Extensive language support (40+ programming languages and frameworks)
- Large, active community with frequent updates
- Highly configurable with extensive customization options
- Docker support for easy CI/CD integration
- Regular releases and active development
- Full control over generated code structure through templates

**Weaknesses**
- Code quality varies significantly between different language generators
- Complex configuration with potentially overwhelming options
- Requires Java runtime environment
- Inconsistent documentation quality across generators

### Hand coded client library


### AI-generated client library


### Combination approach

As part of the Autorest documentation, Microsoft state that the Azure SDK libraries are built by generating the core of each client using Autorest, then adding hand-coded "convenience layer" on top (see https://devblogs.microsoft.com/azure-sdk/code-generation-with-autorest/).

This approach would allow us to take the benefits of code generation for the majority of the code, whilst allowing us to provide a simple and consistent interface and client for consumers of Marain APIs.

**Advantages**
- Majority of the code generated automatically
- Interfaces can remain consistent even if the underlying code generation tool is changed in future

**Disadvantages**
- Requires more work than simply using the generated code directly.

## Decision

Use Kiota to generate the core of the client libraries and build a convenience layer over the top to simplify use and allow clients to easily mock the dependency.

## Consequences
