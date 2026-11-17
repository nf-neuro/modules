process SEGMENTATION_SHIVAI {
    tag "$meta.id"
    label 'process_medium'

    container 'stanislasthoumyre/shivai:2.0.0'

    input:
        tuple val(meta), path(t1), path(flair), path(swi)

    output:
        tuple val(meta), path("*__pvs_map.nii.gz")      , emit: pvs_map     , optional: true
        tuple val(meta), path("*__wmh_map.nii.gz")      , emit: wmh_map     , optional: true
        tuple val(meta), path("*__cmb_map.nii.gz")      , emit: cmb_map     , optional: true
        tuple val(meta), path("*__lac_map.nii.gz")      , emit: lac_map     , optional: true
        tuple val(meta), path("*__brainmask.nii.gz")    , emit: brainmask   , optional: true
        tuple val(meta), path("*__report.pdf")          , emit: report      , optional: true
        path "versions.yml"                             , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    def prediction  = task.ext.prediction  ?: 'all'
    def input_type  = task.ext.input_type  ?: 'standard'
    def brain_seg   = task.ext.brain_seg   ?: 'synthseg'
    def use_cpu             = task.ext.use_cpu             ? '--use_cpu'             : ''
    def ss_qc               = task.ext.ss_qc               ? '--ss_qc'               : ''
    def ss_vol              = task.ext.ss_vol              ? '--ss_vol'              : ''
    def inverse_t2          = task.ext.inverse_t2          ? '--inverse_t2'          : ''
    def use_t1              = task.ext.use_t1              ? '--use_t1'              : ''
    def prereg_flair        = task.ext.prereg_flair        ? '--prereg_flair'        : ''
    def enable_affine_reset = task.ext.enable_affine_reset ? '--enable_affine_reset' : ''
    def keep_all            = task.ext.keep_all            ? '--keep_all'            : ''
    def remove_intermediates= task.ext.remove_intermediates? '--remove_intermediates': ''
    def anonymize           = task.ext.anonymize           ? '--anonymize'           : ''
    def save_graph          = task.ext.save_graph          ? '--save_graph'          : ''
    def preproc_only        = task.ext.preproc_only        ? '--preproc_only'        : ''
    def postproc_only       = task.ext.postproc_only       ? '--postproc_only'       : ''
    def local_synthseg      = task.ext.local_synthseg      ? '--local_synthseg'      : ''
    def ai_threads      = task.ext.ai_threads      != null ? "--ai_threads ${task.ext.ai_threads}"           : ''   // default: 8
    def db_name         = task.ext.db_name                 ? "--db_name ${task.ext.db_name}"                 : ''
    def run_plugin      = task.ext.run_plugin              ? "--run_plugin ${task.ext.run_plugin}"           : ''   // default: Linear
    def max_jobs        = task.ext.max_jobs        != null ? "--max_jobs ${task.ext.max_jobs}"               : ''   // default: 50
    def bcg_ratio       = task.ext.bcg_ratio       != null ? "--bcg_ratio ${task.ext.bcg_ratio}"             : ''   // default: 0.25
    def batch_size      = task.ext.batch_size      != null ? "--batch_size ${task.ext.batch_size}"           : ''   // default: 1
    def percentile      = task.ext.percentile      != null ? "--percentile ${task.ext.percentile}"           : ''   // default: 99
    def threshold       = task.ext.threshold       != null ? "--threshold ${task.ext.threshold}"             : ''   // default: 0.5 (brainmask)
    def threshold_pvs   = task.ext.threshold_pvs   != null ? "--threshold_pvs ${task.ext.threshold_pvs}"     : ''   // default: 0.5
    def threshold_wmh   = task.ext.threshold_wmh   != null ? "--threshold_wmh ${task.ext.threshold_wmh}"     : ''   // default: 0.5
    def threshold_cmb   = task.ext.threshold_cmb   != null ? "--threshold_cmb ${task.ext.threshold_cmb}"     : ''   // default: 0.5
    def threshold_lac   = task.ext.threshold_lac   != null ? "--threshold_lac ${task.ext.threshold_lac}"     : ''   // default: 0.5
    def threshold_clusters = task.ext.threshold_clusters != null ? "--threshold_clusters ${task.ext.threshold_clusters}" : ''
    def min_pvs_size    = task.ext.min_pvs_size    != null ? "--min_pvs_size ${task.ext.min_pvs_size}"       : ''   // default: 10 vox
    def min_wmh_size    = task.ext.min_wmh_size    != null ? "--min_wmh_size ${task.ext.min_wmh_size}"       : ''   // default: 10 vox
    def min_cmb_size    = task.ext.min_cmb_size    != null ? "--min_cmb_size ${task.ext.min_cmb_size}"       : ''   // default: 2 vox
    def min_lac_size    = task.ext.min_lac_size    != null ? "--min_lac_size ${task.ext.min_lac_size}"       : ''   // default: 50 vox
    def final_dimensions = task.ext.final_dimensions       ? "--final_dimensions ${task.ext.final_dimensions}" : '' // default: 160 214 176
    def voxels_size      = task.ext.voxels_size            ? "--voxels_size ${task.ext.voxels_size}"         : ''   // default: 1.0 1.0 1.0
    def voxels_tolerance = task.ext.voxels_tolerance       ? "--voxels_tolerance ${task.ext.voxels_tolerance}" : '' // default: 0.01 0.01 0.01
    def aff_correc_thr   = task.ext.aff_correc_thr != null ? "--aff_correc_thr ${task.ext.aff_correc_thr}"  : ''    // default: 0.3
    def swi_file_num     = task.ext.swi_file_num   != null ? "--swi_file_num ${task.ext.swi_file_num}"      : ''    // default: 0 (first echo)
    def prev_qc          = task.ext.prev_qc                ? "--prev_qc ${task.ext.prev_qc}"                : ''
    def prev_results     = task.ext.prev_results           ? "--prev_results ${task.ext.prev_results}"      : ''
    def replace_t1       = task.ext.replace_t1             ? "--replace_t1 ${task.ext.replace_t1}"          : ''
    def replace_flair    = task.ext.replace_flair          ? "--replace_flair ${task.ext.replace_flair}"    : ''
    def replace_swi      = task.ext.replace_swi            ? "--replace_swi ${task.ext.replace_swi}"        : ''
    def custom_lut       = task.ext.custom_lut             ? "--custom_LUT ${task.ext.custom_lut}"          : ''

    """

    mkdir -p shiva_input/${prefix}/t1
    cp $t1 shiva_input/${prefix}/t1/T1.nii.gz

    if [[ -f "$flair" ]]; then
        mkdir -p shiva_input/${prefix}/flair
        cp $flair shiva_input/${prefix}/flair/FLAIR.nii.gz
    fi

    if [[ -f "$swi" ]]; then
        mkdir -p shiva_input/${prefix}/swi
        cp $swi shiva_input/${prefix}/swi/SWI.nii.gz
    fi

    shiva \
        --in shiva_input \
        --out shiva_out \
        --prediction $prediction \
        --input_type $input_type \
        --brain_seg $brain_seg \
        --model /opt/shivai/models \
        --config /opt/shivai/shiva_config.yaml \
        $use_cpu \
        $ss_qc \
        $ss_vol \
        $inverse_t2 \
        $use_t1 \
        $prereg_flair \
        $enable_affine_reset \
        $keep_all \
        $remove_intermediates \
        $anonymize \
        $save_graph \
        $preproc_only \
        $postproc_only \
        $local_synthseg \
        $ai_threads \
        $db_name \
        $run_plugin \
        $max_jobs \
        $bcg_ratio \
        $batch_size \
        $percentile \
        $threshold \
        $threshold_pvs \
        $threshold_wmh \
        $threshold_cmb \
        $threshold_lac \
        $threshold_clusters \
        $min_pvs_size \
        $min_wmh_size \
        $min_cmb_size \
        $min_lac_size \
        $final_dimensions \
        $voxels_size \
        $voxels_tolerance \
        $aff_correc_thr \
        $swi_file_num \
        $prev_qc \
        $prev_results \
        $replace_t1 \
        $replace_flair \
        $replace_swi \
        $custom_lut

    find shiva_out/results/${prefix} \\
        -name "*pvs*map*.nii.gz" ! -name "*brainmask*" \\
        -exec cp {} ${prefix}__pvs_map.nii.gz \\; 2>/dev/null || true

    find shiva_out/results/${prefix} \\
        -name "*wmh*map*.nii.gz" \\
        -exec cp {} ${prefix}__wmh_map.nii.gz \\; 2>/dev/null || true

    find shiva_out/results/${prefix} \\
        -name "*cmb*map*.nii.gz" \\
        -exec cp {} ${prefix}__cmb_map.nii.gz \\; 2>/dev/null || true

    find shiva_out/results/${prefix} \\
        -name "*lac*map*.nii.gz" \\
        -exec cp {} ${prefix}__lac_map.nii.gz \\; 2>/dev/null || true

    find shiva_out/results/${prefix} \\
        -name "*brainmask*.nii.gz" \\
        -exec cp {} ${prefix}__brainmask.nii.gz \\; 2>/dev/null || true

    find shiva_out/results/${prefix} \\
        -name "*.pdf" \\
        -exec cp {} ${prefix}__report.pdf \\; 2>/dev/null || true

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        shivai: \$(shiva --version 2>&1 | grep -oP '(?<=version: )[0-9.]+')
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

    shiva -h

    touch ${prefix}__pvs_map.nii.gz
    touch ${prefix}__wmh_map.nii.gz
    touch ${prefix}__cmb_map.nii.gz
    touch ${prefix}__lac_map.nii.gz
    touch ${prefix}__brainmask.nii.gz
    touch ${prefix}__report.pdf

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        shivai: \$(shiva --version 2>&1 | grep -oP '(?<=version: )[0-9.]+')
    END_VERSIONS
    """
}
