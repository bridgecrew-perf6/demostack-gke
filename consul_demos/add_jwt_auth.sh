#! /bin/bash

VAULT_HOSTNAME=$(kubectl get svc vault-active  -o jsonpath={..annotations.'external-dns\.alpha\.kubernetes\.io\/hostname'})

OIDCDiscoveryURL="https://$VAULT_HOSTNAME:8200/v1/identity/oidc"

#  Failed to create new auth method: Unexpected response code: 500 (rpc error making call: Invalid Auth Method: exactly one of 'JWTValidationPubKeys', 'JWKSURL', or 'OIDCDiscoveryURL' must be set for type "jwt")


echo "Setting up OIDC"
tee consul_jwt_auth_config.json <<EOF >/dev/null
{
    "BoundIssuer": "$OIDCDiscoveryURL",
    "OIDCDiscoveryURL": "$OIDCDiscoveryURL",
    "OIDCDiscoveryCACert": "$(awk '{printf "%s\\n", $0}' cluster-1-ca.pem)",
    "ClaimMappings": {
        "aud": "service"
    }
}
EOF

consul acl auth-method create -type=jwt \
    -namespace=webapp \
    -name=vault-jwt \
    -description="Consul JWT auth method to receive Vault generated JWTs" \
    -config=@consul_jwt_auth_config.json

rm consul_jwt_auth_config.json


consul acl binding-rule list -method=vault-jwt -format=json | jq -r .[].ID | awk '{ print "consul acl binding-rule delete -id " $1}' | bash || true
consul acl binding-rule list -namespace=webapp -method=vault-jwt -format=json | jq -r .[].ID | awk '{ print "consul acl binding-rule delete -id " $1}' | bash || true

consul acl binding-rule create \
    -namespace=webapp \
    -method=vault-jwt \
    -bind-type=service \
    -description='Auth method created for Services using Vault JWTs' \
    -bind-name='${value.service}' || true

consul acl binding-rule create \
    -namespace=webapp \
    -method=vault-jwt \
    -bind-type=role \
    -description='Auth method created for Roles using Vault JWTs' \
    -bind-name='${value.service}' || true

echo "### Using a pre-created token for login"
consul login -type=jwt \
    -method=vault-jwt \
    -namespace=webapp \
    -token-sink-file=example.consul.token \
    -meta=host=127.0.0.1 \
    -meta=method=vault-jwt \
    -bearer-token-file=example.vault.token

echo "### Reading created token properties"
consul acl token read -token-file=example.consul.token -self

# consul login -type=jwt -method=vault-jwt
# consul acl auth-method create -type oidc \
#     -name=simple-oidc \
#     -max-token-ttl=5m \
#     -config=@auth_config.json || true

# # resetting bind rules
# consul acl binding-rule list -method=simple-oidc -format=json | jq -r .[].ID | awk '{ print "consul acl binding-rule delete -id " $1}' | bash || true

# consul acl binding-rule create \
#     -method=simple-oidc \
#     -bind-type=role \
#     -bind-name=eng-ro \
#     -selector='engineering in list.groups' || true

# consul acl binding-rule create \
#     -method=simple-oidc \
#     -bind-type=service \
#     -bind-name='eng-${value.first_name}' \
#     -selector='engineering in list.groups' || true
