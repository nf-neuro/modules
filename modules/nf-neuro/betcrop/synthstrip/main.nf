process BETCROP_SYNTHSTRIP {
    tag "$meta.id"
    label 'process_single'

    container "${ task.ext.gpu ?
        "freesurfer/synthstrip:1.8-gpu" :
        "freesurfer/synthstrip:1.8"}"
    containerOptions {
        (workflow.containerEngine == 'docker') ? '--entrypoint ""' : ''
    }

    input:
    tuple val(meta), path(image), path(weights) /* optional, input = [] */

    output:
    tuple val(meta), path("*__bet_image.nii.gz"), emit: bet_image
    tuple val(meta), path("*__brain_mask.nii.gz"), emit: brain_mask
    path "versions.yml"           , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    def gpu = task.ext.gpu ? "--gpu" : ""
    def nthreads_freesurfer = task.ext.single_thread ? "--threads 1" : "--threads $task.cpus"
    def border = task.ext.border ? "-b " + task.ext.border : ""
    def nocsf = task.ext.nocsf ? "--no-csf" : ""
    def model = "$weights" ? "--model $weights" : ""

    """
    export OMP_NUM_THREADS=${task.ext.single_thread ? 1 : task.cpus}

    unset PYTHONNOUSERSITE
    mri_synthstrip -i $image --out ${prefix}__bet_image.nii.gz --mask ${prefix}__brain_mask.nii.gz $gpu $nthreads_freesurfer $border $nocsf $model

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        synthstrip: 1.8
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    set +e
    function handle_code () {
    local code=\$?
    ignore=( 1 )
    [[ " \${ignore[@]} " =~ " \$code " ]] || exit \$code
    }
    trap 'handle_code' ERR

    mri_synthstrip -h

    touch ${prefix}__bet_image.nii.gz
    touch ${prefix}__brain_mask.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        synthstrip: 1.8
    END_VERSIONS
    """
}
