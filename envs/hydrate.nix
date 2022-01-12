{ namespaces, components }:

{ lib, config, terralib, ... }:

let

  inherit (terralib) allowS3For;
  bucketArn = "arn:aws:s3:::${config.cluster.s3Bucket}";
  allowS3ForBucket = allowS3For bucketArn;

  inherit (terralib) var id;
  c = "create";
  r = "read";
  u = "update";
  d = "delete";
  l = "list";
  s = "sudo";

  secretsFolder = "encrypted";
  starttimeSecretsPath = "kv/nomad-cluster";
  # starttimeSecretsPath = "starttime"; # TODO: migrate job configs; use variables/constants -> nomadlib
  runtimeSecretsPath = "runtime";

in {
  # cluster level
  # --------------
  tf.hydrate.configuration = {

    resource.vault_policy = builtins.foldl' (old: ns:
      old // {
        "read-iohk-${ns}" = {
          name = "read-iohk-${ns}";
          policy = builtins.toJSON {
            path."${runtimeSecretsPath}/data/${ns}/signer".capabilities =
              [ r l ];
          };
        };
      }) { } namespaces;

    locals.policies = {
      vault.admin = {
        path."auth/userpass/users/*".capabilities = [ c r u d l ];
        path."sys/auth/userpass".capabilities = [ c r u d l s ];
      };
      vault.developer = {
        path."kv/*".capabilities = [ c r u d l ]; # TODO: remove
      };

      # -------------------------
      # nixos reconciliation loop
      # TODO: migrate to more reliable tf reconciliation loop
      consul.developer = {
        service_prefix."cardano-dev-*" = {
          policy = "write";
          intentions = "write";
        };
      };
      nomad.developer = {
        host_volume."cardano-dev-*".policy = "write";
        namespace."cardano-dev" = {
          policy = "write";
          capabilities = [
            "submit-job"
            "dispatch-job"
            "read-logs"
            "alloc-exec"
            "alloc-node-exec"
            "alloc-lifecycle"
          ];
        };
        namespace."cardano-*" = {
          policy = "read";
          capabilities = [
            "submit-job"
            "dispatch-job"
            "read-logs"
            "alloc-exec"
            "alloc-node-exec"
            "alloc-lifecycle"
          ];
        };
      };
    };

  };

  # application secrets
  # --------------
  tf.secrets-hydrate.configuration = let
    _componentsXNamespaces = (lib.cartesianProductOfSets {
      namespace = namespaces;
      component = components;
      stage = [ "runtime" "starttime" ];
    });

    secretFile = g:
      ./.
      + "/${secretsFolder}/${g.namespace}/${g.component}-${g.namespace}-${g.stage}.enc.yaml";
    hasSecretFile = g: builtins.pathExists (secretFile g);

    secretsData.sops_file = builtins.foldl' (old: g:
      old // (lib.optionalAttrs (hasSecretFile g) {
        # Decrypting secrets from the files
        "${g.component}-secrets-${g.namespace}-${g.stage}".source_file =
          "${secretFile g}";
      })) { } _componentsXNamespaces;

    secretsResource.vault_generic_secret = builtins.foldl' (old: g:
      old // (lib.optionalAttrs (hasSecretFile g)
        (if g.stage == "starttime" then {
          # Loading secrets into the generic kv secrets resource
          "${g.component}-${g.namespace}-${g.stage}" = {
            path = "${starttimeSecretsPath}/${g.namespace}/${g.component}";
            data_json = var
              "jsonencode(yamldecode(data.sops_file.${g.component}-secrets-${g.namespace}-${g.stage}.raw))";
          };
        } else {
          # Loading secrets into the generic kv secrets resource
          "${g.component}-${g.namespace}-${g.stage}" = {
            path = "${runtimeSecretsPath}/${g.namespace}/${g.component}";
            data_json = var
              "jsonencode(yamldecode(data.sops_file.${g.component}-secrets-${g.namespace}-${g.stage}.raw))";
          };
        }))) { } _componentsXNamespaces;

    userpassSetup.vault_generic_endpoint = builtins.foldl' (old: ns:
      old // {
        "iohk-signer-${ns}" = let
          user = var ''
            data.sops_file.signer-secrets-${ns}-starttime.data["vaultUsername"]'';
          password = ''
            data.sops_file.signer-secrets-${ns}-starttime.data["vaultPassword"]'';
        in {
          path = "auth/userpass/users/${user}";
          ignore_absent_fields = true;
          data_json = var ''
            jsonencode({"policies" = [ "read-iohk-${ns}" ], "password" = ${password}})'';
        };
      }) { } namespaces;

  in {
    data = secretsData;
    resource = secretsResource // userpassSetup;
  };

  # application state
  # --------------
  tf.app-hydrate.configuration = let in { };
}
