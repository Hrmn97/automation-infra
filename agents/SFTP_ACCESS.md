# SFTP Access to OpenClaw Agents

This guide explains how to access agents via SFTP/SCP through AWS Systems Manager Session Manager tunneling.

## Why Not Direct SSH?

The agents are deployed in private subnets with **zero inbound security group rules** for security:
- ✅ No exposed SSH ports (no attack surface)
- ✅ All access audited through CloudTrail
- ✅ IAM-based authentication (no SSH keys to manage)
- ✅ Works without public IPs or bastion hosts

## Prerequisites

1. **AWS Session Manager Plugin** installed:
   ```bash
   brew install --cask session-manager-plugin  # macOS
   ```

2. **SSH configured on the agent** (you've already done this):
   - SSH daemon running
   - User account with password authentication enabled
   - User home directory with proper permissions

3. **AWS credentials** with SSM permissions

## Quick Start

### Option 1: Using the Makefile

```bash
# In one terminal, start the tunnel (keep it running)
cd /path/to/sf-terraform/agents
make sftp-london
```

This will:
1. Look up the instance ID from Terraform state
2. Start an SSM port forwarding session (port 2222 → port 22)
3. Display connection instructions
4. Keep the tunnel open until you press Ctrl+C

### Option 2: Using the Script Directly

```bash
./scripts/sftp-tunnel.sh agent-one
```

## Usage Examples

Once the tunnel is running, open a **new terminal** and use:

### SFTP Interactive Session

```bash
sftp -P 2222 agent-one@localhost
```

Commands in SFTP session:
```
sftp> pwd                    # Show remote directory
sftp> ls                     # List remote files
sftp> lcd ~/Downloads        # Change local directory
sftp> get remote-file.txt    # Download file
sftp> put local-file.txt     # Upload file
sftp> exit                   # Close connection
```

### SCP - Upload Files

```bash
# Upload a single file
scp -P 2222 /path/to/local-file.txt agent-one@localhost:/home/agent-one/

# Upload multiple files
scp -P 2222 *.log agent-one@localhost:/home/agent-one/logs/

# Upload directory recursively
scp -P 2222 -r /path/to/local-dir agent-one@localhost:/home/agent-one/
```

### SCP - Download Files

```bash
# Download a single file
scp -P 2222 agent-one@localhost:/home/agent-one/remote-file.txt .

# Download multiple files
scp -P 2222 agent-one@localhost:'/home/agent-one/*.log' ./logs/

# Download directory recursively
scp -P 2222 -r agent-one@localhost:/home/agent-one/data ./
```

## FileZilla Configuration

1. **Start the tunnel** in a terminal:
   ```bash
   make sftp-london
   ```

2. **Open FileZilla** and configure a new site:
   - **Host:** `localhost`
   - **Port:** `2222`
   - **Protocol:** `SFTP - SSH File Transfer Protocol`
   - **Logon Type:** `Normal`
   - **User:** `agent-one` (or the username you created)
   - **Password:** (the password you set on the instance)

3. **Connect** - you should see the remote file system

## rsync Over the Tunnel

```bash
# Sync local directory to remote
rsync -avz -e "ssh -p 2222" /path/to/local/ agent-one@localhost:/home/agent-one/remote/

# Sync remote directory to local
rsync -avz -e "ssh -p 2222" agent-one@localhost:/home/agent-one/remote/ /path/to/local/
```

## Troubleshooting

### "Connection refused" or "No route to host"

**Issue:** The tunnel isn't running or died.

**Solution:** 
1. Check if the tunnel terminal is still open
2. Restart the tunnel: `make sftp-london`
3. Wait a few seconds for the connection to establish

### "Permission denied (publickey)"

**Issue:** Either:
- The agent's SSH daemon isn't configured for password auth
- The user account doesn't exist or has no password

**Solution (on the agent):**
1. Connect via SSM: `make connect-london`
2. Check SSH config:
   ```bash
   sudo grep -E "^(PasswordAuthentication|ChallengeResponseAuthentication)" /etc/ssh/sshd_config
   ```
   Should show:
   ```
   PasswordAuthentication yes
   ```
3. Restart SSH:
   ```bash
   sudo systemctl restart sshd
   ```
4. Verify user has a password:
   ```bash
   sudo passwd agent-one  # Set/reset password
   ```

### "Host key verification failed"

**Issue:** SSH is rejecting the host key (first connection or host key changed).

**Solution:**
```bash
# Remove old host key for localhost:2222
ssh-keygen -R "[localhost]:2222"

# Or disable strict checking (less secure)
sftp -P 2222 -o StrictHostKeyChecking=no agent-one@localhost
```

### Session Manager plugin not found

**Issue:** AWS CLI can't find the Session Manager plugin.

**Solution:**
```bash
# Install the plugin
brew install --cask session-manager-plugin

# Verify installation
session-manager-plugin
```

### "Target instance not connected"

**Issue:** The SSM agent on the instance isn't running or can't reach SSM endpoints.

**Solution:**
1. Check instance state: `make status-london`
2. If stopped, start it via AWS Console
3. If running, restart SSM agent:
   ```bash
   make connect-london
   sudo systemctl restart amazon-ssm-agent
   ```

## Security Considerations

### What This Does

✅ Creates an encrypted tunnel through AWS SSM (TLS over HTTPS)
✅ Forwards local port 2222 to remote port 22 on the agent
✅ All traffic encrypted end-to-end
✅ All connections logged in CloudTrail
✅ No inbound security group rules required
✅ No public IP addresses required

### What This Doesn't Do

❌ Expose the agent to the internet
❌ Create any permanent network routes
❌ Require SSH keys to be distributed
❌ Bypass IAM authentication (you still need valid AWS credentials)

### Best Practices

1. **Keep tunnels short-lived** - only run when needed
2. **Use strong passwords** on agent user accounts
3. **Audit regularly** - check CloudTrail for SSM sessions
4. **Consider key-based auth** - more secure than passwords (see below)
5. **Restrict IAM permissions** - only grant SSM access to authorized users

## Advanced: SSH Key Authentication (Recommended)

Instead of passwords, use SSH keys for better security:

1. **Generate a key pair** (on your local machine):
   ```bash
   ssh-keygen -t ed25519 -C "agent-one-access" -f ~/.ssh/agent-one
   ```

2. **Copy public key to agent** (via SSM):
   ```bash
   make connect-london
   ```
   Then on the agent:
   ```bash
   mkdir -p ~/.ssh
   chmod 700 ~/.ssh
   cat >> ~/.ssh/authorized_keys << 'EOF'
   [paste your public key here from ~/.ssh/agent-one.pub]
   EOF
   chmod 600 ~/.ssh/authorized_keys
   ```

3. **Use the key** (with tunnel running):
   ```bash
   sftp -P 2222 -i ~/.ssh/agent-one agent-one@localhost
   ```

4. **Optional: Disable password auth** (more secure):
   ```bash
   # On the agent
   sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
   sudo systemctl restart sshd
   ```

## Alternative: S3 for File Transfer

If SFTP is overkill, consider using S3 as a file transfer intermediary:

```bash
# On your local machine
aws s3 cp local-file.txt s3://your-bucket/transfers/

# On the agent (via SSM)
aws s3 cp s3://your-bucket/transfers/local-file.txt /home/agent-one/

# The agent already has S3 access via IAM role (check outputs.tf)
```

This approach:
- ✅ No port forwarding needed
- ✅ Works with large files
- ✅ Files persisted in S3
- ✅ Versioned and encrypted
- ❌ Two-step process
- ❌ S3 storage costs

## Related Commands

```bash
make connect-london        # Interactive SSM session (shell)
make dashboard-london      # Port-forward OpenClaw dashboard (HTTP)
make logs-london           # View OpenClaw logs
make status-london         # Check OpenClaw service status
make restart-london        # Restart OpenClaw service
```

## Support

For issues with:
- **Tunnel not starting**: Check AWS credentials and Session Manager plugin
- **SSH connection failing**: Check sshd config and user setup on agent
- **File transfer errors**: Check permissions on remote directories
- **Performance issues**: Consider S3 for large files

---

**Remember:** The tunnel must stay open in its terminal while you use SFTP/SCP in another terminal.
