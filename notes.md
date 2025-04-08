
Deploy ISO to libvirtd machine

    rsync -avz -P ./result/iso/nixos.iso tester:/tmp

    virt-install --connect qemu+ssh://tester/system \
        --name "test-remote-deploy" \
        --hvm \
        --osinfo "nixos-unstable" \
        --memory=8000 \
        --vcpu 4 \
        --disk target.bus=sata,size=10 \
        --disk target.bus=sata,size=10 \
        --network network=default \
        --cdrom /tmp/nixos.iso \
        --serial pty \
        --graphics none \
        --noautoconsole \
        --transient
