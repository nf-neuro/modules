process IMAGE_MATH {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilpy:2.2.2_cpu"

    input:
        tuple val(meta), path(images), val(value) /* optional = null */

    output:
        tuple val(meta), path("*.nii.gz")        , emit: image
        path "versions.yml"                      , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.suffix ?: "output"
    def used_value = task.ext.value != null ? task.ext.value : value != null ? value : ""
    def data_type = task.ext.data_type ?: "float32"
    def exclude_background = task.ext.exclude_background ? "--exclude_background" : ""

    def operations = [
        'absolute_value',
        'addition',
        'blur',
        'ceil',
        'closing',
        'concatenate',
        'convert',
        'correlation',
        'difference',
        'dilation',
        'division',
        'erosion',
        'floor',
        'intersection',
        'invert',
        'log_10',
        'log_e',
        'lower_clip',
        'lower_threshold',
        'lower_threshold_eq',
        'lower_threshold_otsu',
        'mean',
        'multiplication',
        'normalize_sum',
        'normalize_max',
        'opening',
        'round',
        'std',
        'subtraction',
        'union',
        'upper_clip',
        'upper_threshold',
        'upper_threshold_eq',
        'upper_threshold_otsu',
    ]

    assert task.ext.operation in operations : "Invalid operation: ${task.ext.operation}. " +
        "Must be one of ${operations}"

    """
    scil_volume_math ${task.ext.operation} $images $used_value \
        ${prefix}_${suffix}.nii.gz --data_type $data_type $exclude_background -f

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.suffix ?: "output"

    """
    scil_volume_math -h
    touch ${prefix}__${suffix}.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
