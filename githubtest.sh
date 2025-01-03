name: Build and Release Kernel

on:
  push:
    branches:
      - main # Change to your main branch name

jobs:
  build:
    runs-on: ubuntu-latest
    container: ubuntu:latest # Use a container for consistent environment
    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Install dependencies
        run: |
          apt-get update
          apt-get install -y --no-install-recommends \
            zip bc bison flex g++-multilib gcc-multilib libc6-dev-i386 \
            lib32ncurses5-dev x11proto-core-dev libx11-dev lib32z1-dev \
            libgl1-mesa-glx libxml2-utils xsltproc unzip repo git curl \
            python3 python3-pip # Install python3 and pip
          pip3 install pyyaml # Install PyYAML for potential config parsing

      - name: Install repo (using specific version)
        run: |
          mkdir -p ~/bin
          curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
          chmod a+x ~/bin/repo
          export PATH=$PATH:~/bin

      - name: Create build directory
        run: mkdir -p builds

      - name: Set build variables
        id: build_vars
        run: |
          BUILD_DATE=$(date +'%Y-%m-%d-%H-%M-%S')
          echo "::set-output name=date::$BUILD_DATE"
          echo "::set-output name=root_dir::OP12-A15-${BUILD_DATE}-release"
          echo "::set-output name=zip_name::Anykernel3-OP-A15-android14-6.1-KernelSU-SUSFS-${BUILD_DATE}.zip"
          echo "::set-output name=release_tag::v$(date +'%Y.%m.%d-%H%M%S')"


      - name: Clone repositories
        run: |
          cd builds
          mkdir -p ${{ steps.build_vars.outputs.root_dir }}
          cd ${{ steps.build_vars.outputs.root_dir }}
          git clone https://github.com/TheWildJames/AnyKernel3.git -b android14-5.15
          git clone https://gitlab.com/simonpunk/susfs4ksu.git -b gki-android14-6.1
          git clone https://github.com/TheWildJames/kernel_patches.git

      - name: Get the kernel
        run: |
          cd builds/${{ steps.build_vars.outputs.root_dir }}
          mkdir oneplus12_v
          cd oneplus12_v
          repo init -u https://github.com/OnePlusOSS/kernel_manifest.git -b oneplus/sm8650 -m oneplus12_v.xml
          repo sync -j$(nproc)
          rm -rf ./kernel_platform/common/android/abi_gki_protected_exports_*

      - name: Add KernelSU
        run: |
          cd builds/${{ steps.build_vars.outputs.root_dir }}/oneplus12_v/kernel_platform
          curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next/kernel/setup.sh" | bash -s next-susfs-a14-6.1
          cd KernelSU-Next/kernel
          sed -i 's/ccflags-y += -DKSU_VERSION=16/ccflags-y += -DKSU_VERSION=12113/' ./Makefile

      - name: Configure Kernel
        run: |
          cd builds/${{ steps.build_vars.outputs.root_dir }}/oneplus12_v
          echo "CONFIG_KSU=y" >> ./common/arch/arm64/configs/gki_defconfig
          # ... (rest of your config options)
          sed -i '2s/check_defconfig//' ./kernel_platform/common/build.config.gki

      - name: Build Kernel
        run: |
          cd builds/${{ steps.build_vars.outputs.root_dir }}/oneplus12_v
          ./kernel_platform/oplus/build/oplus_build_kernel.sh pineapple gki

      - name: Copy Image.lz4
        run: |
          cd builds/${{ steps.build_vars.outputs.root_dir }}/oneplus12_v
          cp ./out/dist/Image.lz4 ../AnyKernel3/Image

      - name: Create zip file
        run: |
          cd builds/${{ steps.build_vars.outputs.root_dir }}/AnyKernel3
          zip -r ../${{ steps.build_vars.outputs.zip_name }} ./*

      - name: Create GitHub Release
        uses: actions/create-release@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          tag_name: ${{ steps.build_vars.outputs.release_tag }}
          release_name: OP12 A15 android14-6.1 With KernelSU & SUSFS ${{ steps.build_vars.outputs.date }}
          body: Kernel release
          draft: false
          prerelease: false
          artifacts: builds/${{ steps.build_vars.outputs.root_dir }}/${{ steps.build_vars.outputs.zip_name }}
