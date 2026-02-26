
process IMAGE_CROPVOLUME {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilpy:2.2.1_cpu"

    input:
    tuple val(meta), path(image), path(bounding_box)

    output:
    tuple val(meta), path("*_cropped.nii.gz"), emit: image
    tuple val(meta), path("*.pkl")           , emit: bounding_box, optional: true
    path "versions.yml"                      , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    def input_bbox = bounding_box ? "--input_bbox $bounding_box" : ""
    def suffix = task.ext.first_suffix ? "${task.ext.first_suffix}_cropped" : "cropped"
    def output_bbox = task.ext.output_bbox ? "--output_bbox ${prefix}_${suffix}_bbox.pkl" : ""

    """
    scil_volume_crop $image ${prefix}_${suffix}.nii.gz $input_bbox $output_bbox

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.first_suffix ? "${task.ext.first_suffix}_cropped" : "cropped"

    """
    scil_volume_crop -h

    touch ${prefix}_${suffix}.nii.gz

    if $task.ext.output_bbox;
    then
        touch ${prefix}_${suffix}_bbox.pkl
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
