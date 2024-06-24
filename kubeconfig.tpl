apiVersion: v1
clusters:
- cluster:
    server: ${endpoint}
    certificate-authority-data: ${ca_data}
  name: ${cluster_name}
contexts:
- context:
    cluster: ${cluster_name}
    user: aws
  name: ${cluster_name}
current-context: ${cluster_name}
kind: Config
preferences: {}
users:
- name: aws
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1alpha1
      command: aws
      args:
        - eks
        - get-token
        - --region
        - ${region}
        - --cluster-name
        - ${cluster_name}
