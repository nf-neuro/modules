
process RECONST_IHMT {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilpy:2.2.1_cpu"

    input:
    tuple val(meta), path(altpn), path(altnp), path(pos), path(neg), path(mtoff_pd),
        path(mtoff_t1), path(mask), path(jsons), val(acq_params), path(b1), path(b1_fit)

    output:
    tuple val(meta), path("ihMT_native_maps")        , emit: ihmt_maps
    tuple val(meta), path("Complementary_maps")      , emit: comp_maps, optional: true
    path "versions.yml"                              , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    def extended = task.ext.extended ? "--extended" : ""
    def filtering = task.ext.filtering ? "--filtering" : ""
    def set_jsons = jsons ? "--in_jsons $jsons" : ""
    def set_acq_params = acq_params ? "--in_acq_parameters ${acq_params.join(" ")}" : ""
    def set_mtoff_t1 = mtoff_t1 ? "--in_mtoff_t1 $mtoff_t1" : ""
    def set_mask = mask ? "--mask $mask" : ""
    def set_b1 = b1 ? "--in_B1_map $b1" : ""
    def set_b1_method = task.ext.b1_correction_method ? "--B1_correction_method " + task.ext.b1_correction_method : ""
    def set_b1_fitvalues = b1_fit ? "--B1_fitvalues $b1_fit" : ""
    def b1_nominal = task.ext.b1_nominal ? "--B1_nominal " + task.ext.b1_nominal : ""
    def b1_smooth = task.ext.b1_smooth ? "--B1_smooth_dims " + task.ext.b1_smooth : ""

    """
    scil_mti_maps_ihMT . --in_altpn $altpn --in_altnp $altnp --in_positive $pos \
        --in_negative $neg --in_mtoff_pd $mtoff_pd $set_mtoff_t1 --out_prefix $prefix \
        $set_mask $set_jsons $set_acq_params $set_b1 $set_b1_method \
        $set_b1_fitvalues $b1_nominal $b1_smooth $extended $filtering

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    scil_mti_maps_ihMT -h
    mkdir ihMT_native_maps
    mkdir Complementary_maps

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
