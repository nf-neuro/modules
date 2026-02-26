process CONNECTIVITY_DECOMPOSE {
    tag "$meta.id"
    label 'process_high'

    container "scilus/scilpy:2.2.1_cpu"

    input:
    tuple val(meta), path(trk), path(labels)

    output:
    tuple val(meta), path("*__decomposed.h5")       , emit: hdf5
    tuple val(meta), path("*__labels_list.txt")     , emit: labels_list
    path "versions.yml"                             , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def no_pruning = task.ext.no_pruning ? "--no_pruning" : ""
    def no_remove_loops = task.ext.no_remove_loops ? "--no_remove_loops" : ""
    def no_remove_outliers = task.ext.no_remove_outliers ? "--no_remove_outliers" : ""
    def no_remove_curv = task.ext.no_remove_curv ? "--no_remove_curv" : ""

    def min_len = task.ext.min_len ? "--min_len " + task.ext.min_len : ""
    def max_len = task.ext.max_len ? "--max_len " + task.ext.max_len : ""
    def outlier_threshold = task.ext.outlier_threshold ? "--outlier_threshold " + task.ext.outlier_threshold : ""
    def max_angle = task.ext.max_angle ? "--loop_max_angle " + task.ext.max_angle : ""
    def max_curv = task.ext.max_curv ? "--curv_qb_distance " + task.ext.max_curv : ""

    """

    scil_tractogram_segment_connections_from_labels $trk  $labels \
        "${prefix}__decomposed.h5" --processes $task.cpus \
        --out_labels_list "${prefix}__labels_list.txt" \
        $no_pruning $no_remove_loops $no_remove_outliers \
        $no_remove_curv $min_len $max_len $outlier_threshold \
        $max_angle $max_curv


    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    touch ${prefix}__decomposed.h5
    touch ${prefix}__labels_list.txt

    scil_tractogram_segment_connections_from_labels -h

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
