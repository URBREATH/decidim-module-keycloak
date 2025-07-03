# Decidim::Keycloak

**Provided by:** Platoniq

***

## Description

This tool provides an **OmniAuth strategy for Keycloak**, enabling user authentication through a Keycloak server within a Decidim application. It seamlessly integrates Keycloak as an identity provider.

***

## Images

*Login screen showing the Keycloak option:*
![Login with Keycloak](https://raw.githubusercontent.com/Platoniq/decidim-module-keycloak/main/examples/login.png)

*System configuration for the Keycloak module:*
![System Configuration](https://raw.githubusercontent.com/Platoniq/decidim-module-keycloak/main/examples/system_conf.gif)

***

## Installation Prerequisites

Before installing this module, ensure you have a working **Decidim application** with its basic dependencies, such as **Ruby** and **PostgreSQL**.

***

## Installation Instructions

Follow these steps to deploy and configure the module:

1.  **Add the gem to your Gemfile**. Open your application's `Gemfile` and add the following line:
    ```ruby
    gem "decidim-keycloak", git: "[https://github.com/Platoniq/decidim-module-keycloak](https://github.com/Platoniq/decidim-module-keycloak)", branch: "main"
    ```

2.  **Install the gem**. Run the bundler from your terminal to install the new dependency:
    ```bash
    bundle
    ```

3.  **Configure secrets**. Add your Keycloak OAuth credentials to the `config/secrets.yml` file.
    ```yaml
      omniauth:
        keycloakopenid:
          enabled: true
          icon_path: media/images/keycloak_logo.svg
          client_id: <%= ENV["KEYCLOAK_CLIENT_ID"] %>
          client_secret: <%= ENV["KEYCLOAK_CLIENT_SECRET"] %>
          site: <%= ENV["KEYCLOAK_SITE"] %>
          realm: <%= ENV["KEYCLOAK_REALM"] %>
    ```

4.  **Set Environment Variables**. Define the following environment variables in your deployment environment. You can also configure these values directly in the Decidim admin panel for each organization.
    ```
    KEYCLOAK_CLIENT_ID=your-client-id
    KEYCLOAK_CLIENT_SECRET=your-client-secret
    KEYCLOAK_SITE=[https://your-keycloak-server.com](https://your-keycloak-server.com)
    KEYCLOAK_REALM=your-realm-name
    ```

***

## License

This project is licensed under the **GNU AFFERO GENERAL PUBLIC LICENSE v3.0**. See the [LICENSE-AGPLv3.txt](https://github.com/Platoniq/decidim-module-keycloak/blob/main/LICENSE-AGPLv3.txt) file for details.

***

## External technical resources

-   **[Source Code Repository](https://github.com/Platoniq/decidim-module-keycloak)**: The official GitHub repository for this module.
-   **[Decidim Project](https://github.com/decidim/decidim)**: The main repository for the Decidim framework.
