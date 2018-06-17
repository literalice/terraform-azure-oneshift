# 1 Node OpenShift on Azure

## Azure上でVMを作成する

Azureで以下の条件のVM作成します。

* RHEL 7
* Standard D4s v3 (4 vcpu 数、16 GB メモリ)
* sshログイン
* セキュリティグループの設定で自マシンのIPからポート22、8443、80、443を通すルールを追加する

## OpenShiftが使用する、Azureの認証情報を作成する

OpenShiftがストレージをAzureのManaged Diskから払い出せるよう、Azureの認証情報を作成します。

ローカルマシンのazコマンドでAzureにログインしたあと、以下のコマンドを実行してください。

1. サービスプリンシパルの作成
   以下コマンドで、OCPが使うサービスアカウントを作成します。パスワードとサブスクリプションID、リソースグループ名を変更してください。
   
   ```bash
   az ad sp create-for-rbac --name openshiftcloudprovider \
    --password <任意のパスワード> --role contributor \
    --scopes /subscriptions/<サブスクリプションID>/resourceGroups/<作成したVMのあるリソースグループ>
   ```
2. 出力されるJSONを控える
  以下のようなJSONが出力されるので、後のステップのために控えておきます。
  
  ```json
  {
  "appId": "xxx-xxx-xxx-xxx",
  "displayName": "openshiftcloudprovider",
  "name": "http://openshiftcloudprovider",
  "password": "<任意のパスワード>",
  "tenant": "xxx-xxx-xxx-xxx-xxxxxxxxx"
  }
  ```

## Azureで設定ファイルを作成する

### Azure上のVMにSSHログインする

Azure上のVMに、VM作成時に指定したユーザー名とパスワードでログインしてください。

また、Azure上でOpenShiftにインストールする際、VM上から自マシンに再ログインするので、フォワードエージェントの設定を行ってください。

https://qiita.com/isaoshimizu/items/84ac5a0b1d42b9d355cf

### OpenShiftのインストーラーをダウンロードする

AzureのVMにログインし、以下コマンドを実行してください。
これにより、VM上にOpenShiftのインストーラーが設定されます。

```bash
sudo su -

subscription-manager register # システムをRHNに登録
subscription-manager list --available --matches="*OpenShift*" # 使用できるサブスクリプションの検索

# Subscription Name:   30 Day Self-Supported Red Hat OpenShift Container Platform, 2-Core Evaluation
# Provides:            Red Hat OpenShift Container Platform
#                      Red Hat Istio
# ...
# Pool ID:             xxxx

subscription-manager attach --pool=xxxx # 上記で出力された評価用サブスクリプションのPool IDの入力する
subscription-manager repos --disable="*" # 余分なリポジトリを無効化する

subscription-manager repos \
    --enable="rhel-7-server-rpms" \
    --enable="rhel-7-server-extras-rpms" \
    --enable="rhel-7-server-ose-3.9-rpms" \
    --enable="rhel-7-fast-datapath-rpms" \
    --enable="rhel-7-server-ansible-2.4-rpms" # 必要なリポジトリを有効化する

 yum -y install atomic-openshift-utils # OpenShiftのインストーラーをインストールする
 yum upgrade # 最新のライブラリにアップデートする
```

### OpenShiftが使用するAzureの設定ファイルを作成

AzureのVMに、Azureの認証情報を設定したファイルを作成します。
OpenShiftは、ストレージをAzureのManaged Diskから払い出す際に、このファイルの情報を参照します。

上記で `az ad` コマンドを実行したときの出力情報から入力します。

```bash
sudo su -
mkdir -p /etc/origin/cloudprovider
vim /etc/origin/cloudprovider/azure.conf

tenantId: xxxx # az adコマンド実行時に出力された"tenant"
subscriptionId: xxx-xxx-xxx-xxx-xxx # AzureのサブスクリプションID
aadClientId: xxx-xxx-xxx-xxxx # az adコマンド実行時に出力された"appId"
aadClientSecret: xxx # az adコマンド実行時に出力された"password"
aadTenantId:  xxxx # az adコマンド実行時に出力された"tenant"(tenantIdと同値)
resourceGroup: ocp # VMのあるリソースグループ名
cloud: AzurePublicCloud # AzurePublicCloud固定
vnetName: ocp-vnet # VMのあるvnet名
securityGroupName: master-nsg # VMに設定されたセキュリティグループ名
location: japaneast # VMのロケーション。東日本の場合はjapaneast
```

### インベントリファイルの作成

AzureのVM上でOpenShiftのインストール用設定ファイルを作成します(非rootユーザー)。

```bash
vi inventory.yml
```

```yml
OSEv3:
  children:
    masters:
      hosts:
        master: ""
    etcd:
      hosts:
        master: ""
    nodes:
      hosts:
        master:
          openshift_node_labels:
            region: infra
  vars:
    ansible_user: azureuser # VMのユーザー名
    ansible_become: true
    oreg_url: "registry.access.redhat.com/openshift3/ose-${component}:${version}"
    openshift_deployment_type: openshift-enterprise
    openshift_release: "v3.9"
    openshift_master_identity_providers: # 認証プロバイダ。ここでは、セキュリティグループでアクセスを制限する前提で、任意のユーザー名、パスワードでログインできるようにしています。
      - name: 'test_identity_provider'
        login: true
        challenge: true
        kind: 'AllowAllPasswordIdentityProvider'
    os_sdn_network_plugin_name: 'redhat/openshift-ovs-networkpolicy'
    openshift_disable_check: 'disk_availability,memory_availability'
    openshift_master_cluster_hostname: master # VMにログインしたときにプロンプトに表示される内部ホスト名
    openshift_master_cluster_public_hostname: master.ocp.example.com # masterのDNS名。DNSが無い場合は、インストール後アクセスするマシンのhostsファイルを変更する
    openshift_master_default_subdomain: app.ocp.example.com # OCPでデプロイしたアプリのデフォルトサブドメイン。DNSが無い場合は、インストール後アクセスするマシンのhostsファイルを変更する
    osm_default_node_selector: "region=infra"
    openshift_cloudprovider_kind: azure
    osm_controller_args:
      cloud-provider:
      - azure
      cloud-config:
      - /etc/origin/cloudprovider/azure.conf
    osm_api_server_args:
      cloud-provider:
      - azure
      cloud-config:
      - /etc/origin/cloudprovider/azure.conf

```

### インストールの実行

AzureのVMで以下コマンドを実行し、OpenShiftをインストールします(非rootユーザー)。

```bash
ansible-playbook -i inventory.yml /usr/share/ansible/openshift-ansible/playbooks/prerequisites.yml
ansible-playbook -i inventory.yml /usr/share/ansible/openshift-ansible/playbooks/deploy_cluster.yml
```

インストールが終了したら、 https://master.ocp.example.com:8443 にアクセスしてWebコンソールが表示されることを確認してください。

`Timeout (12s) waiting for privilege escalation prompt: ` で止まる場合は、何度か deploy_cluster.yml を再実行してください。

### StorageClassの作成

VM上で以下ファイルを作成し、OpenShiftが標準で使用するStorageClassを作成します。

```yaml
# ~/storageclass.yml
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: standard
provisioner: kubernetes.io/azure-disk
parameters:
  storageaccounttype: Standard_LRS
  kind: managed
```

上記をOpenShiftに適用します。

```bash
oc apply -f storageclass.yml
```

また、OpenShiftがデフォルトで使用するStorageClassを上記に設定します。

```bash
oc patch storageclass standard -p '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": "true"}}}'
```

oc get scコマンドで設定を確認できます。

```bash
oc get sc
NAME                PROVISIONER                AGE
standard (default)   kubernetes.io/azure-disk   22h
```

### ログ集約機能の有効化

inventoryファイルに以下の行を追記します。

```yaml
    ...
    openshift_logging_install_logging: true
    openshift_logging_es_pvc_dynamic: true
    openshift_logging_es_memory_limit: 512M
```

ログ集約機能をインストールします。

```bash
 ansible-playbook -i inventory.yml /usr/share/ansible/openshift-ansible/playbooks/openshift-logging/config.yml
 ```

### メトリクス機能の有効化

inventoryファイルに以下の行を追記します。

```yaml
    ...
    openshift_metrics_install_metrics: true
    openshift_metrics_cassandra_storage_type: dynamic
```

メトリクス機能をインストールします。

```bash
ansible-playbook -i ~/inventory.yml /usr/share/ansible/openshift-ansible/playbooks/openshift-metrics/config.yml
```