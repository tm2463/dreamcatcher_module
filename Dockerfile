FROM rocker/r-ver:4.2.0

ENV DEBIAN_FRONTEND=noninteractive
ENV RETICULATE_MINICONDA_ENABLED=FALSE

# Use Posit Package Manager for CRAN binaries
RUN echo "options(repos = c(CRAN='https://packagemanager.posit.co/cran/__linux__/jammy/latest'))" \
    >> $(R --no-echo --no-save -e "cat(Sys.getenv('R_HOME'))")/etc/Rprofile.site

# Use Posit Package Manager for Bioconductor binaries
RUN R -e "options(BioC_mirror='https://packagemanager.posit.co/bioconductor')"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    libhdf5-dev libcurl4-openssl-dev libssl-dev libpng-dev libboost-all-dev libxml2-dev \
    openjdk-8-jdk python3-dev python3-pip wget git libfftw3-dev libgsl-dev pkg-config \
    pigz zlib1g-dev libncurses5-dev libncursesw5-dev libbz2-dev liblzma-dev \
    libdeflate-dev libfontconfig1-dev pbzip2 llvm-10 libgeos-dev \
    hisat2 bowtie2 samtools && \
    ln -s /usr/bin/python3 /usr/local/bin/python && \
    rm -rf /var/lib/apt/lists/*

RUN LLVM_CONFIG=/usr/lib/llvm-10/bin/llvm-config pip3 install \
    llvmlite \
    numpy==1.24.4 \
    scikit-learn==1.3.2 \
    umap-learn==0.5.5 \
    umi_tools==1.1.6 && \
    apt clean && rm -rf /var/lib/apt/lists/*

RUN git clone --branch v1.2.1 https://github.com/KlugerLab/FIt-SNE.git && \
    mkdir -p /usr/local/bin && \
    g++ -std=c++11 -O3 \
        FIt-SNE/src/sptree.cpp \
        FIt-SNE/src/tsne.cpp \
        FIt-SNE/src/nbodyfft.cpp \
        -o /usr/local/bin/fast_tsne \
        -pthread -lfftw3 -lm && \
    rm -rf FIt-SNE

# --------------------------
# R / Bioconductor / Seurat
# Use multiple layers for caching
# --------------------------

# 1. Install Matrix (needed by many packages)
RUN R -e "install.packages('https://cran.r-project.org/src/contrib/Archive/Matrix/Matrix_1.6-4.tar.gz', repos=NULL, type='source')"

# 2. Install core CRAN packages
RUN R -e "install.packages(c('VGAM','R.utils','metap','Rfast2','ape','enrichR','mixtools','spatstat.explore','spatstat.geom','hdf5r','rgeos','dplyr','igraph','remotes','Seurat'))"

# 3. Install BiocManager
RUN R -e "install.packages('BiocManager')"

# 4. Install Bioconductor packages
RUN R -e "BiocManager::install(c('multtest','S4Vectors','SummarizedExperiment','SingleCellExperiment','MAST','DESeq2','BiocGenerics','GenomicRanges','IRanges','rtracklayer','monocle','Biobase','limma','glmGamPoi'), ask=FALSE)"

# 5. Install GitHub package
RUN R -e "remotes::install_github('mojaveazure/seurat-disk')"

ARG kuniq_version=1.0.4
RUN wget --no-check-certificate https://github.com/fbreitwieser/krakenuniq/archive/refs/tags/v${kuniq_version}.tar.gz && \
    tar -xvf v${kuniq_version}.tar.gz -C /opt && \
    cd /opt/krakenuniq-${kuniq_version} && \
    ./install_krakenuniq.sh /usr/local/bin && \
    cd / && rm v${kuniq_version}.tar.gz

RUN cd /opt && \
    git clone https://github.com/apredeus/subread_precision && \
    cd subread_precision/src && make -f Makefile.Linux

ARG bbmap_version=39.15
RUN wget https://sourceforge.net/projects/bbmap/files/BBMap_${bbmap_version}.tar.gz && \
    tar -xzf BBMap_${bbmap_version}.tar.gz -C /opt && \
    cd /opt/bbmap && ./stats.sh in=resources/phix174_ill.ref.fa.gz && \
    cd / && rm BBMap_${bbmap_version}.tar.gz

ENV PATH="${PATH}:/opt/subread_precision/bin:/opt/bbmap"

ARG hisat_version=2.2.1
ARG bowtie_version=2.5.1
ARG samtools_version=1.21
ARG umitools_version=1.1.6
ARG subread_version=2.0.2

RUN echo "hisat2 version: ${hisat_version}" >> versions.txt && \
    echo "bowtie2 version: ${bowtie_version}" >> versions.txt && \
    echo "samtools version: ${samtools_version}" >> versions.txt && \
    echo "UMI-tools version: ${umitools_version}" >> versions.txt && \
    echo "krakenuniq version: ${kuniq_version}" >> versions.txt && \
    echo "subread version: ${subread_version}" >> versions.txt && \
    echo "BBMap version: ${bbmap_version}" >> versions.txt

COPY . /opt/dreamcatcher
RUN chmod +x /opt/dreamcatcher/dreamcatcher
ENV PATH="/opt/dreamcatcher:${PATH}"

RUN apt-get purge -y git g++ llvm-10 && \
    apt-get autoremove -y && \
    apt-get clean

WORKDIR /opt/dreamcatcher

CMD ["dreamcatcher"]