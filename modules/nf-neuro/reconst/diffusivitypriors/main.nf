process RECONST_DIFFUSIVITYPRIORS {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilpy:2.2.1_cpu"

    input:
        tuple val(meta), path(fa), path(ad), path(rd), path(md)

    output:
        tuple val(meta), path("*_para_diff.txt")  , emit: para_diff_file
        tuple val(meta), path("*_iso_diff.txt")   , emit: iso_diff_file
        tuple val(meta), path("*_perp_diff.txt")  , emit: perp_diff_file, optional: true

        tuple val(meta), env('mean_para_diff')    , emit: mean_para_diff
        tuple val(meta), env('std_para_diff')     , emit: std_para_diff
        tuple val(meta), env('min_para_diff')     , emit: min_para_diff
        tuple val(meta), env('max_para_diff')     , emit: max_para_diff
        tuple val(meta), env('mean_iso_diff')     , emit: mean_iso_diff
        tuple val(meta), env('std_iso_diff')      , emit: std_iso_diff
        tuple val(meta), env('min_iso_diff')      , emit: min_iso_diff
        tuple val(meta), env('max_iso_diff')      , emit: max_iso_diff
        tuple val(meta), env('mean_perp_diff')    , emit: mean_perp_diff, optional: true
        tuple val(meta), env('std_perp_diff')     , emit: std_perp_diff, optional: true
        tuple val(meta), env('min_perp_diff')     , emit: min_perp_diff, optional: true
        tuple val(meta), env('max_perp_diff')     , emit: max_perp_diff, optional: true

        path "versions.yml"                       , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    def fa_min = task.ext.fa_min ? "--fa_min " + task.ext.fa_min : ""
    def fa_max = task.ext.fa_max ? "--fa_max " + task.ext.fa_max : ""
    def md_min = task.ext.md_min ? "--md_min " + task.ext.md_min : ""
    def roi_radius = task.ext.roi_radius ? "--roi_radius " + task.ext.roi_radius : ""

    """

    scil_NODDI_priors $fa $ad $rd $md $fa_min $fa_max $md_min $roi_radius \
        --out_txt_1fiber_para ${prefix}_para_diff.txt \
        --out_txt_1fiber_perp ${prefix}_perp_diff.txt \
        --out_txt_ventricles ${prefix}_iso_diff.txt

    # Set output environment variables
    echo "Setting output environment variables"
    read mean_para_diff std_para_diff min_para_diff max_para_diff < <(awk 'NR==2' ${prefix}_para_diff.txt)
    echo "Done para"
    read mean_iso_diff std_iso_diff min_iso_diff max_iso_diff < <(awk 'NR==2' ${prefix}_iso_diff.txt)
    echo "Done iso"
    if [[ -e ${prefix}_perp_diff.txt ]]
    then
        read mean_perp_diff std_perp_diff min_perp_diff max_perp_diff < <(awk 'NR==2' ${prefix}_perp_diff.txt)
        echo "Done perp"
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    scil_NODDI_priors -h

    touch ${prefix}_para_diff.txt
    touch ${prefix}_iso_diff.txt
    touch ${prefix}_perp_diff.txt

    # Set output environment variables
    mean_para_diff=0.5
    std_para_diff=0.5
    min_para_diff=0.5
    max_para_diff=0.5
    mean_iso_diff=0.5
    std_iso_diff=0.5
    min_iso_diff=0.5
    max_iso_diff=0.5
    mean_perp_diff=0.5
    std_perp_diff=0.5
    min_perp_diff=0.5
    max_perp_diff=0.5

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
