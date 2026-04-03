process SEGMENTATION_SYNTHSEG {
    tag "$meta.id"
    label 'process_medium'

    container "freesurfer/freesurfer:7.4.1"

    input:
    tuple val(meta), path(image), path(lesion), path(fs_license)

    output:
    tuple val(meta), path("*__mask_wm.nii.gz")                , emit: wm_mask
    tuple val(meta), path("*__mask_gm.nii.gz")                , emit: gm_mask
    tuple val(meta), path("*__mask_csf.nii.gz")               , emit: csf_mask
    tuple val(meta), path("*__map_wm.nii.gz")                 , emit: wm_map
    tuple val(meta), path("*__map_gm.nii.gz")                 , emit: gm_map
    tuple val(meta), path("*__map_csf.nii.gz")                , emit: csf_map
    tuple val(meta), path("*__seg.nii.gz")                    , emit: seg, optional: true
    tuple val(meta), path("*__aparc_aseg.nii.gz")             , emit: aparc_aseg, optional: true
    tuple val(meta), path("*__resampled_image.nii.gz")        , emit: resample, optional: true
    tuple val(meta), path("*__volume.csv")                    , emit: volume, optional: true
    tuple val(meta), path("*__qc_score.csv")                  , emit: qc_score, optional: true
    path "versions.yml"                                       , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def gpu = task.ext.gpu ? "" : "--cpu"
    def gm_parc = task.ext.gm_parc ? "--parc" : ""
    def robust = task.ext.robust ? "--robust" : ""
    def fast = task.ext.fast ? "--fast" : ""
    def ct = task.ext.ct ? "--ct" : ""
    def output_resample = task.ext.output_resample ? "--resample ${prefix}__resampled_image.nii.gz" : ""
    def output_volume = task.ext.output_volume ?  "--vol ${prefix}__volume.csv" : ""
    def output_qc_score = task.ext.output_qc_score ?  "--qc ${prefix}__qc_score.csv" : ""
    def crop = task.ext.crop ? "--crop " + task.ext.crop: ""
    def nthreads = task.ext.single_thread ? 1 : task.cpus

    """
    export OMP_NUM_THREADS=${task.ext.single_thread ? 1 : task.cpus}

    cp $fs_license \$FREESURFER_HOME/license.txt

    mri_synthseg --i $image --o seg.nii.gz --threads $nthreads --post posteriors.nii.gz $gpu $robust $fast $ct $output_resample $output_volume $output_qc_score $crop

    if [[ -n "$gm_parc" ]];
    then
        # Cortical grey matter parcellation
        mv seg.nii.gz ${prefix}__aparc_aseg.nii.gz

        # WM Mask
        mri_binarize --i ${prefix}__aparc_aseg.nii.gz \
            --match 2 7 10 12 13 16 28 41 46 49 51 52 60 \
            --o ${prefix}__mask_wm.nii.gz

        # GM Mask
        mri_binarize --i ${prefix}__aparc_aseg.nii.gz \
            --match 8 11 17 18 26 47 50 53 54 58 1001 1002 1003 1004 1005 1006 1007 1008 1009 1010 1011 1012 1013 1014 1015 1016 1017 1018 1019 1020 1021 1022 1023 1024 1025 1026 1027 1028 1029 1030 1031 1032 1033 1034 1035 2001 2002 2003 2004 2005 2006 2007 2008 2009 2010 2011 2012 2013 2014 2015 2016 2017 2018 2019 2020 2021 2022 2023 2024 2025 2026 2027 2028 2029 2030 2031 2032 2033 2034 2035 \
            --o ${prefix}__mask_gm.nii.gz

        # CSF Mask
        mri_binarize --i ${prefix}__aparc_aseg.nii.gz \
            --match 4 5 14 15 24 43 44 \
            --o ${prefix}__mask_csf.nii.gz

    else
        mv seg.nii.gz ${prefix}__seg.nii.gz

        # WM Mask
        mri_binarize --i ${prefix}__seg.nii.gz \
            --match 2 7 10 12 13 16 28 41 46 49 51 52 60 \
            --o ${prefix}__mask_wm.nii.gz

        # GM Mask
        mri_binarize --i ${prefix}__seg.nii.gz \
            --match 3 8 11 17 18 26 42 47 50 53 54 58 \
            --o ${prefix}__mask_gm.nii.gz

        # CSF Mask
        mri_binarize --i ${prefix}__seg.nii.gz \
            --match 4 5 14 15 24 43 44 \
            --o ${prefix}__mask_csf.nii.gz
    fi

    # Posteriors 4D slices associated with wm, gm and csf masks.
    wm_map_indices=(1 5 7 9 10 13 18 19 23 25 27 28 32)
    gm_map_indices=(2 6 8 14 15 17 20 24 26 29 30 31)
    csf_map_indices=(3 4 11 12 16 21 22)

    # Generating concat command
    wm_map_command="mri_concat --sum --o ${prefix}__map_wm.nii.gz"
    gm_map_command="mri_concat --sum --o ${prefix}__map_gm.nii.gz"
    csf_map_command="mri_concat --sum --o ${prefix}__map_csf.nii.gz"

    # Extracting wm slices for wm map
    for i in "\${wm_map_indices[@]}"; do
        mri_convert -nth "\$i" posteriors.nii.gz wm_map_slice_\${i}.nii.gz
        wm_map_command="\$wm_map_command --i wm_map_slice_\${i}.nii.gz"
    done

    # Extracting gm slices for gm map
    for i in "\${gm_map_indices[@]}"; do
        mri_convert -nth "\$i" posteriors.nii.gz gm_map_slice_\${i}.nii.gz
        gm_map_command="\$gm_map_command --i gm_map_slice_\${i}.nii.gz"
    done

    # Extracting csf slices for csf map
    for i in "\${csf_map_indices[@]}"; do
        mri_convert -nth "\$i" posteriors.nii.gz csf_map_slice_\${i}.nii.gz
        csf_map_command="\$csf_map_command --i csf_map_slice_\${i}.nii.gz"
    done

    eval \${wm_map_command}
    eval \${gm_map_command}
    eval \${csf_map_command}

    rm wm_map_slice_*.nii.gz
    rm gm_map_slice_*.nii.gz
    rm csf_map_slice_*.nii.gz

    if [[ -f "$lesion" ]];
    then
        mri_binarize --i ${prefix}__mask_wm.nii.gz --merge $lesion --min 0.5 --o ${prefix}__mask_wm.nii.gz
    fi

    mri_convert -i ${prefix}__mask_wm.nii.gz --out_data_type uchar -o ${prefix}__mask_wm.nii.gz
    mri_convert -i ${prefix}__mask_gm.nii.gz --out_data_type uchar -o ${prefix}__mask_gm.nii.gz
    mri_convert -i ${prefix}__mask_csf.nii.gz --out_data_type uchar -o ${prefix}__mask_csf.nii.gz

    rm \$FREESURFER_HOME/license.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        Freesurfer: \$(mri_convert -version | grep "freesurfer" | sed -E 's/.* ([0-9.]+).*/\\1/')
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

    mri_synthseg --help
    mri_binarize --help
    mri_convert --help

    touch ${prefix}__mask_wm.nii.gz
    touch ${prefix}__mask_gm.nii.gz
    touch ${prefix}__mask_csf.nii.gz
    touch ${prefix}__map_wm.nii.gz
    touch ${prefix}__map_gm.nii.gz
    touch ${prefix}__map_csf.nii.gz
    touch ${prefix}__seg.nii.gz
    touch ${prefix}__aparc_aseg.nii.gz
    touch ${prefix}__resampled_image.nii.gz
    touch ${prefix}__volume.csv
    touch ${prefix}__qc_score.csv


    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        Freesurfer: \$(mri_convert -version | grep "freesurfer" | sed -E 's/.* ([0-9.]+).*/\\1/')
    END_VERSIONS
    """
}
