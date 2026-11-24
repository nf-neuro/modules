process SEGMENTATION_SHIVAI {
    tag "$meta.id"
    label 'process_high'

    container 'stanislasthoumyre/shivai:2.0.0'

    input:
        tuple val(meta), path(t1), path(flair), path(swi)

    output:
        tuple val(meta), path("*_seg-pvs_*.nii.gz")   , emit: pvs_dseg  , optional: true
        tuple val(meta), path("*_seg-wmh_*.nii.gz")   , emit: wmh_dseg  , optional: true
        tuple val(meta), path("*_seg-cmb_*.nii.gz")   , emit: cmb_dseg  , optional: true
        tuple val(meta), path("*_seg-lac_*.nii.gz")   , emit: lac_dseg  , optional: true
        tuple val(meta), path("*__shivai_report.pdf") , emit: report    , optional: true
        path "versions.yml"                           , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    def prediction  = task.ext.prediction  ?: 'all'
    def input_type  = task.ext.input_type  ?: 'standard'
    def brain_seg   = task.ext.brain_seg   ?: 'shiva'

    def inverse_t2       = task.ext.inverse_t2              ? '--inverse_t2'                                  : ''
    def use_t1           = task.ext.use_t1                  ? '--use_t1'                                      : ''
    def prereg_flair     = task.ext.prereg_flair            ? '--prereg_flair'                                : ''
    def preproc_only     = task.ext.preproc_only            ? '--preproc_only'                                : ''
    def postproc_only    = task.ext.postproc_only           ? '--postproc_only'                               : ''
    def threads          = task.ext.single_thread           ? 1                                               : (task.ext.ai_threads ?: task.cpus)
    def use_cpu          = task.ext.use_cpu         != null ? (task.ext.use_cpu ? '--use_cpu' : '')           : '--use_cpu'
    def percentile       = task.ext.percentile      != null ? "--percentile ${task.ext.percentile}"           : ''   // default: 99
    def threshold        = task.ext.threshold       != null ? "--threshold ${task.ext.threshold}"             : ''   // default: 0.5
    def threshold_pvs    = task.ext.threshold_pvs   != null ? "--threshold_pvs ${task.ext.threshold_pvs}"     : ''   // default: 0.5
    def threshold_wmh    = task.ext.threshold_wmh   != null ? "--threshold_wmh ${task.ext.threshold_wmh}"     : ''   // default: 0.5
    def threshold_cmb    = task.ext.threshold_cmb   != null ? "--threshold_cmb ${task.ext.threshold_cmb}"     : ''   // default: 0.5
    def threshold_lac    = task.ext.threshold_lac   != null ? "--threshold_lac ${task.ext.threshold_lac}"     : ''   // default: 0.5
    def min_pvs_size     = task.ext.min_pvs_size    != null ? "--min_pvs_size ${task.ext.min_pvs_size}"       : ''   // default: 10 vox
    def min_wmh_size     = task.ext.min_wmh_size    != null ? "--min_wmh_size ${task.ext.min_wmh_size}"       : ''   // default: 10 vox
    def min_cmb_size     = task.ext.min_cmb_size    != null ? "--min_cmb_size ${task.ext.min_cmb_size}"       : ''   // default: 2 vox
    def min_lac_size     = task.ext.min_lac_size    != null ? "--min_lac_size ${task.ext.min_lac_size}"       : ''   // default: 50 vox
    def final_dimensions = task.ext.final_dimensions        ? "--final_dimensions ${task.ext.final_dimensions}" : '' // default: 160 214 176
    def voxels_size      = task.ext.voxels_size             ? "--voxels_size ${task.ext.voxels_size}"         : ''   // default: 1.0 1.0 1.0
    def voxels_tolerance = task.ext.voxels_tolerance        ? "--voxels_tolerance ${task.ext.voxels_tolerance}" : '' // default: 0.01 0.01 0.01
    """
    export OMP_NUM_THREADS=${threads}
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=${threads}
    export PATH="/opt/shivai-venv/bin:/opt/SynthSeg/scripts:/opt/ants-2.4.3/bin:\$PATH"

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
        --ai_threads ${threads}  \
        $use_cpu \
        $inverse_t2 \
        $use_t1 \
        $prereg_flair \
        $preproc_only \
        $postproc_only \
        $percentile \
        $threshold \
        $threshold_pvs \
        $threshold_wmh \
        $threshold_cmb \
        $threshold_lac \
        $min_pvs_size \
        $min_wmh_size \
        $min_cmb_size \
        $min_lac_size \
        $final_dimensions \
        $voxels_size \
        $voxels_tolerance

    find shiva_out/results/segmentations/pvs_segmentation/${prefix} \\
        -name "*labelled*pvs.nii.gz" \\
        -exec cp {} ${prefix}_space-FLAIR_seg-pvs_desc-shivai_dseg.nii.gz \\; 2>/dev/null || true

    find shiva_out/results/segmentations/wmh_segmentation/${prefix} \\
        -name "*labelled*wmh.nii.gz" \\
        -exec cp {} ${prefix}_space-FLAIR_seg-wmh_desc-shivai_dseg.nii.gz  \\; 2>/dev/null || true

    find shiva_out/results/segmentations/cmb_segmentation_swi-space/${prefix} \\
        -name "*labelled*cmb.nii.gz" \\
        -exec cp {} ${prefix}_space-swi_seg-cmb_desc-shivai_dseg.nii.gz  \\; 2>/dev/null || true

    find shiva_out/results/segmentations/lac_segmentation/${prefix} \\
        -name "*labelled*lac.nii.gz" \\
        -exec cp {} ${prefix}_space-FLAIR_seg-lac_desc-shivai_dseg.nii.gz  \\; 2>/dev/null || true

    find shiva_out/results/report/${prefix} \\
        -name "*.pdf" \\
        -exec cp {} ${prefix}__shivai_report.pdf \\; 2>/dev/null || true

    rm -rf shiva_input shiva_out .cache

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        shivai: \$(shiva --version 2>/dev/null | grep -oE '^[0-9]+(\\.[0-9]+)+\$' | tail -n 1)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def prediction = task.ext.prediction ?: 'all'

    """
    set +e
    function handle_code () {
        local code=\$?
        ignore=( 1 )
        [[ " \${ignore[@]} " =~ " \$code " ]] || exit \$code
    }
    trap 'handle_code' ERR

    export PATH="/opt/shivai-venv/bin:\$PATH"

    shiva -h

    if ( ($prediction == 'all' || $prediction.contains('PVS')) && [[ -f "$flair" ]] ) {
        touch ${prefix}_space-FLAIR_seg-pvs_desc-shivai_dseg.nii.gz
    }
    if ( ($prediction == 'all' || $prediction.contains('WMH')) && [[ -f "$flair" ]] ) {
        touch ${prefix}_space-FLAIR_seg-wmh_desc-shivai_dseg.nii.gz
    }
    if ( ($prediction == 'all' || $prediction.contains('CMB')) && [[ -f "$swi" ]] ) {
        touch ${prefix}_space-swi_seg-cmb_desc-shivai_dseg.nii.gz
    }
    if ( ($prediction == 'all' || $prediction.contains('LAC')) && [[ -f "$flair" ]] ) {
        touch ${prefix}_space-FLAIR_seg-lac_desc-shivai_dseg.nii.gz
    }
    touch ${prefix}__shivai_report.pdf

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        shivai: \$(shiva --version 2>/dev/null | grep -oE '^[0-9]+(\\.[0-9]+)+\$' | tail -n 1)
    END_VERSIONS
    """
}
