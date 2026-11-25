process TENSOR_RATIO {
    tag "$meta.id"
    label 'process_single'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://scil.usherbrooke.ca/containers/scilus_2.0.2.sif':
        'scilus/scilus:latest' }"

    input:
        tuple val(meta), path(image)

    output:
        tuple val(meta), path("*_Dxx_to_Dyy.nii.gz")        , emit: tensor_x_to_y
        tuple val(meta), path("*_Dxx_to_Dzz.nii.gz")        , emit: tensor_x_to_z
        path "versions.yml"                                 , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    fslsplit $image
    fslmaths ${image}_0000.nii.gz -div ${image}_0003.nii.gz ${prefix}_Dxx_to_Dyy.nii.gz
    fslmaths ${image}_0000.nii.gz -div ${image}_0005.nii.gz ${prefix}_Dxx_to_Dzz.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fsl: \$(fslsplit -version 2>&1 | sed -n 's/FSLSPLIT version \\([0-9.]\\+\\)/\\1/p')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    touch ${prefix}_Dxx_to_Dyy.nii.gz
    touch ${prefix}_Dxx_to_Dzz.nii.gz
    fslsplit
    fslmaths

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fsl: \$(fslsplit -version 2>&1 | sed -n 's/FSLSPLIT version \\([0-9.]\\+\\)/\\1/p')
    END_VERSIONS
    """
}
