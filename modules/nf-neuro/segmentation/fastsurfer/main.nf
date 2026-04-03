process SEGMENTATION_FASTSURFER {
    tag "$meta.id"
    label 'process_single'

    container "${ 'deepmi/fastsurfer:cpu-v2.4.2' }"
    containerOptions((workflow.containerEngine == 'docker') ? '--entrypoint "" --user $(id -u):$(id -g)' : '')

    input:
        tuple val(meta), path(anat), path(fs_license)

    output:
        tuple val(meta), path("*_fastsurfer")       , emit: fastsurferdirectory
        path "versions.yml"                         , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def acq3T = task.ext.acq3T ? "--3T" : ""
    def cerebnet = task.ext.cerebnet ? "" : "--no_cereb"
    def hypvinn = task.ext.hypvinn ? "" : "--no_hypothal"
    def seg_only = task.ext.seg_only ? "--seg_only" : ""
    def nthreads = task.ext.single_thread ? 1 : task.cpus
    def FASTSURFER_HOME = "/fastsurfer"
    def SUBJECTS_DIR = "${prefix}_fastsurfer"

    """
    export OMP_NUM_THREADS=${task.ext.single_thread ? 1 : task.cpus}

    mkdir ${prefix}_fastsurfer/
    $FASTSURFER_HOME/run_fastsurfer.sh  --allow_root \
                                        --sd \$(realpath ${SUBJECTS_DIR}) \
                                        --fs_license \$(realpath $fs_license) \
                                        --t1 \$(realpath ${anat}) \
                                        --sid ${prefix} \
                                        --threads $nthreads \
                                        --py python3 \
                                        $cerebnet \
                                        $hypvinn \
                                        $seg_only \
                                        $acq3T

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fastsurfer: \$($FASTSURFER_HOME/run_fastsurfer.sh --version)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def FASTSURFER_HOME = "/fastsurfer"

    """
    set +e
    function handle_code () {
    local code=\$?
    ignore=( 1 )
    [[ " \${ignore[@]} " =~ " \$code " ]] || exit \$code
    }
    trap 'handle_code' ERR

    $FASTSURFER_HOME/run_fastsurfer.sh --version

    mkdir -p ${prefix}__fastsurfer/${prefix}/mri/transforms \
        ${prefix}__fastsurfer/${prefix}/label/ \
        ${prefix}__fastsurfer/${prefix}/surf/ \
        ${prefix}__fastsurfer/${prefix}/stats/ \
        ${prefix}__fastsurfer/${prefix}/scripts/ \
        ${prefix}__fastsurfer/${prefix}/tmp/ \
        ${prefix}__fastsurfer/${prefix}/touch/

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fastsurfer: \$($FASTSURFER_HOME/run_fastsurfer.sh --version)
    END_VERSIONS
    """
}
