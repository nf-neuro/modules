process TRACTOGRAM_MATH {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "scilus/scilpy:2.2.1_cpu"

    input:
        tuple val(meta), path(trks), path(reference)

    output:
        tuple val(meta), path("*.trk"), emit: trk
        path "versions.yml"           , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    assert task.ext.operation in ['difference', 'intersection', 'union',
        'concatenate', 'lazy_concatenate'] : "Invalid operation: ${task.ext.operation}. " +
        "Must be one of [difference, intersection, union, concatenate, lazy_concatenate]"

    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.suffix ?: ""
    def precision = task.ext.precision ? "--precision ${task.ext.precision}" : ""
    def robust = task.ext.robust ? "--robust" : ""
    def no_metadata = task.ext.no_metadata ? "--no_metadata" : ""
    def fake_metadata = task.ext.fake_metadata ? "--fake_metadata" : ""
    def save_indices = task.ext.save_indices ? "--save_indices ${prefix}__indices.json" : ""
    def save_empty = task.ext.save_empty ? "--save_empty" : ""
    def no_bbox_check = task.ext.no_bbox_check ? "--no_bbox_check" : ""
    reference = reference ? "--reference ${reference}" : ""

    """
    scil_tractogram_math $task.ext.operation $trks \
        ${prefix}__${suffix}.trk \
        $precision \
        $robust \
        $no_metadata \
        $fake_metadata \
        $save_indices \
        $save_empty \
        $no_bbox_check \
        $reference \
        -v -f

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.suffix ?: ""
    """
    touch ${prefix}__${suffix}.trk

    scil_tractogram_math -h

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
